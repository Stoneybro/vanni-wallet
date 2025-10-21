// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {AidraSmartWallet} from "../src/AidraSmartWallet.sol";
import {AidraSmartWalletFactory} from "../src/AidraSmartWalletFactory.sol";

contract AidraSmartWalletFactoryTest is Test {
    AidraSmartWalletFactory public factory;
    AidraSmartWallet public implementation;

    address public owner1 = makeAddr("owner1");
    address public owner2 = makeAddr("owner2");
    address public owner3 = makeAddr("owner3");

    event AccountCreated(address indexed account, address indexed owner);

    function setUp() public {
        // Deploy implementation contract
        implementation = new AidraSmartWallet(makeAddr("registry"));

        // Deploy factory with implementation
        factory = new AidraSmartWalletFactory(address(implementation));
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_Success() public view {
        // Verify implementation is set correctly
        assertEq(factory.implementation(), address(implementation));
    }

    function test_Constructor_RevertsIfImplementationNotDeployed() public {
        address emptyAddress = makeAddr("empty");

        vm.expectRevert(AidraSmartWalletFactory.AidraSmartWalletFactory__ImplementationUndeployed.selector);
        new AidraSmartWalletFactory(emptyAddress);
    }

    function test_Constructor_RevertsIfImplementationIsZeroAddress() public {
        vm.expectRevert(AidraSmartWalletFactory.AidraSmartWalletFactory__ImplementationUndeployed.selector);
        new AidraSmartWalletFactory(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                    CREATE SMART ACCOUNT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreateSmartAccount_Success() public {
        vm.startPrank(owner1);

        // Predict the address
        address predictedAddress = factory.getPredictedAddress(owner1);

        // Expect AccountCreated event
        vm.expectEmit(true, true, false, false);
        emit AccountCreated(predictedAddress, owner1);

        // Create account
        address account = factory.createSmartAccount(owner1);

        // Verify account was created at predicted address
        assertEq(account, predictedAddress);

        // Verify account has code (was deployed)
        assertTrue(account.code.length > 0);

        // Verify owner is set correctly
        AidraSmartWallet wallet = AidraSmartWallet(payable(account));
        assertEq(wallet.s_owner(), owner1);

        vm.stopPrank();
    }

    function test_CreateSmartAccount_ReturnsSameAddressIfAlreadyDeployed() public {
        vm.startPrank(owner1);

        // Create account first time
        address account1 = factory.createSmartAccount(owner1);

        // Create account second time - should return same address
        address account2 = factory.createSmartAccount(owner1);

        // Verify same address returned
        assertEq(account1, account2);

        vm.stopPrank();
    }

    function test_CreateSmartAccount_NoEventOnSecondCall() public {
        vm.startPrank(owner1);

        // Create account first time
        factory.createSmartAccount(owner1);

        // Second call should not emit event
        vm.recordLogs();
        factory.createSmartAccount(owner1);

        // Verify no events were emitted
        assertEq(vm.getRecordedLogs().length, 0);

        vm.stopPrank();
    }

    function test_CreateSmartAccount_DifferentOwnersGetDifferentAccounts() public {
        // Create account for owner1
        vm.prank(owner1);
        address account1 = factory.createSmartAccount(owner1);

        // Create account for owner2
        vm.prank(owner2);
        address account2 = factory.createSmartAccount(owner2);

        // Verify different addresses
        assertTrue(account1 != account2);

        // Verify correct owners
        assertEq(AidraSmartWallet(payable(account1)).s_owner(), owner1);
        assertEq(AidraSmartWallet(payable(account2)).s_owner(), owner2);
    }

    function test_CreateSmartAccount_MultipleUsers() public {
        address[] memory owners = new address[](5);
        address[] memory accounts = new address[](5);

        // Create accounts for multiple users
        for (uint256 i = 0; i < 5; i++) {
            owners[i] = makeAddr(string(abi.encodePacked("owner", i)));
            vm.prank(owners[i]);
            accounts[i] = factory.createSmartAccount(owners[i]);
        }

        // Verify all accounts are unique
        for (uint256 i = 0; i < 5; i++) {
            for (uint256 j = i + 1; j < 5; j++) {
                assertTrue(accounts[i] != accounts[j]);
            }
        }

        // Verify all owners are set correctly
        for (uint256 i = 0; i < 5; i++) {
            assertEq(AidraSmartWallet(payable(accounts[i])).s_owner(), owners[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                CREATE SMART ACCOUNT FOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreateSmartAccountFor_Success() public {
        // Anyone can call createSmartAccount for any owner
        vm.startPrank(owner2); // owner2 creates account for owner1

        // Predict the address
        address predictedAddress = factory.getPredictedAddress(owner1);

        // Expect AccountCreated event
        vm.expectEmit(true, true, false, false);
        emit AccountCreated(predictedAddress, owner1);

        // Create account for owner1
        address account = factory.createSmartAccount(owner1);

        // Verify account was created at predicted address
        assertEq(account, predictedAddress);

        // Verify account has code (was deployed)
        assertTrue(account.code.length > 0);

        // Verify owner is set correctly to owner1 (not owner2)
        AidraSmartWallet wallet = AidraSmartWallet(payable(account));
        assertEq(wallet.s_owner(), owner1);

        vm.stopPrank();
    }

    function test_CreateSmartAccountFor_ReturnsSameAddressIfAlreadyDeployed() public {
        // Create account first time for owner2
        vm.prank(owner1);
        address account1 = factory.createSmartAccount(owner2);

        // Create account second time for owner2 from different caller
        vm.prank(owner3);
        address account2 = factory.createSmartAccount(owner2);

        // Verify same address returned
        assertEq(account1, account2);

        // Verify owner is still owner2
        assertEq(AidraSmartWallet(payable(account1)).s_owner(), owner2);
    }

    function test_CreateSmartAccountFor_MatchesCreateSmartAccount() public {
        // Create account using createSmartAccount for owner1
        vm.prank(owner1);
        address account1 = factory.createSmartAccount(owner1);

        // Try to create account for owner2 using createSmartAccount from owner2
        vm.prank(owner2);
        address account2 = factory.createSmartAccount(owner2);

        // Create account for owner3 using createSmartAccount from owner1
        vm.prank(owner1);
        address account3 = factory.createSmartAccount(owner3);

        // Verify all accounts are different
        assertTrue(account1 != account2);
        assertTrue(account1 != account3);
        assertTrue(account2 != account3);

        // Verify owners are correct
        assertEq(AidraSmartWallet(payable(account1)).s_owner(), owner1);
        assertEq(AidraSmartWallet(payable(account2)).s_owner(), owner2);
        assertEq(AidraSmartWallet(payable(account3)).s_owner(), owner3);
    }

    function test_CreateSmartAccountFor_ERC4337Compatible() public {
        // Simulate EntryPoint calling factory
        address entryPoint = makeAddr("entryPoint");
        
        vm.prank(entryPoint);
        address account = factory.createSmartAccount(owner1);

        // Verify account was created for owner1, not entryPoint
        assertEq(AidraSmartWallet(payable(account)).s_owner(), owner1);
        
        // Verify it matches predicted address
        assertEq(account, factory.getPredictedAddress(owner1));
    }

    /*//////////////////////////////////////////////////////////////
                    GET PREDICTED ADDRESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetPredictedAddress_ReturnsCorrectAddress() public {
        // Get predicted address
        address predictedAddress = factory.getPredictedAddress(owner1);

        // Create account
        vm.prank(owner1);
        address actualAddress = factory.createSmartAccount(owner1);

        // Verify prediction was correct
        assertEq(predictedAddress, actualAddress);
    }

    function test_GetPredictedAddress_DifferentOwnersGetDifferentAddresses() public view {
        address predicted1 = factory.getPredictedAddress(owner1);
        address predicted2 = factory.getPredictedAddress(owner2);
        address predicted3 = factory.getPredictedAddress(owner3);

        // Verify all predictions are unique
        assertTrue(predicted1 != predicted2);
        assertTrue(predicted1 != predicted3);
        assertTrue(predicted2 != predicted3);
    }

    function test_GetPredictedAddress_SameOwnerGetsSameAddress() public view {
        address predicted1 = factory.getPredictedAddress(owner1);
        address predicted2 = factory.getPredictedAddress(owner1);

        // Verify same prediction
        assertEq(predicted1, predicted2);
    }

    function test_GetPredictedAddress_WorksBeforeAndAfterDeployment() public {
        // Get prediction before deployment
        address predictedBefore = factory.getPredictedAddress(owner1);

        // Deploy account
        vm.prank(owner1);
        address deployed = factory.createSmartAccount(owner1);

        // Get prediction after deployment
        address predictedAfter = factory.getPredictedAddress(owner1);

        // Verify all addresses match
        assertEq(predictedBefore, deployed);
        assertEq(predictedBefore, predictedAfter);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_CreateSmartAccount_AnyOwner(address owner) public {
        // Skip zero address and precompiles
        vm.assume(owner != address(0));
        vm.assume(uint160(owner) > 10);

        vm.prank(owner);
        address account = factory.createSmartAccount(owner);

        // Verify account was created
        assertTrue(account.code.length > 0);

        // Verify owner is correct
        assertEq(AidraSmartWallet(payable(account)).s_owner(), owner);
    }

    function testFuzz_GetPredictedAddress_MatchesActual(address owner) public {
        // Skip zero address and precompiles
        vm.assume(owner != address(0));
        vm.assume(uint160(owner) > 10);

        address predicted = factory.getPredictedAddress(owner);

        vm.prank(owner);
        address actual = factory.createSmartAccount(owner);

        assertEq(predicted, actual);
    }

    function testFuzz_CreateSmartAccount_Idempotent(address owner, uint8 iterations) public {
        // Skip zero address and precompiles
        vm.assume(owner != address(0));
        vm.assume(uint160(owner) > 10);
        vm.assume(iterations > 0 && iterations <= 10);

        vm.startPrank(owner);

        address firstAccount = factory.createSmartAccount(owner);

        // Call multiple times
        for (uint256 i = 0; i < iterations; i++) {
            address account = factory.createSmartAccount(owner);
            assertEq(account, firstAccount);
        }

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Integration_AccountIsFullyFunctional() public {
        // Create account
        vm.prank(owner1);
        address account = factory.createSmartAccount(owner1);

        AidraSmartWallet wallet = AidraSmartWallet(payable(account));

        // Fund the wallet
        vm.deal(account, 10 ether);

        // Test execute function
        address recipient = makeAddr("recipient");
        vm.prank(owner1);
        wallet.execute(recipient, 1 ether, "");

        // Verify transfer worked
        assertEq(recipient.balance, 1 ether);
        assertEq(account.balance, 9 ether);
    }

    function test_Integration_MultipleAccountsIndependent() public {
        // Create two accounts
        vm.prank(owner1);
        address account1 = factory.createSmartAccount(owner1);

        vm.prank(owner2);
        address account2 = factory.createSmartAccount(owner2);

        // Fund both accounts
        vm.deal(account1, 10 ether);
        vm.deal(account2, 10 ether);

        // Execute from account1
        address recipient1 = makeAddr("recipient1");
        vm.prank(owner1);
        AidraSmartWallet(payable(account1)).execute(recipient1, 1 ether, "");

        // Execute from account2
        address recipient2 = makeAddr("recipient2");
        vm.prank(owner2);
        AidraSmartWallet(payable(account2)).execute(recipient2, 2 ether, "");

        // Verify independent operations
        assertEq(recipient1.balance, 1 ether);
        assertEq(recipient2.balance, 2 ether);
        assertEq(account1.balance, 9 ether);
        assertEq(account2.balance, 8 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EdgeCase_FactoryCanCreateAccountForItself() public {
        vm.prank(address(factory));
        address account = factory.createSmartAccount(address(factory));

        assertTrue(account.code.length > 0);
        assertEq(AidraSmartWallet(payable(account)).s_owner(), address(factory));
    }

    function test_EdgeCase_ImplementationCannotBeInitialized() public {
        // Try to initialize the implementation directly
        vm.expectRevert();
        implementation.initialize(owner1);
    }

    function test_EdgeCase_ProxyCannotBeInitializedTwice() public {
        vm.prank(owner1);
        address account = factory.createSmartAccount(owner1);

        // Try to initialize again
        vm.expectRevert();
        AidraSmartWallet(payable(account)).initialize(owner2);
    }
}
