// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {AidraSmartWallet} from "../src/AidraSmartWallet.sol";
import {AidraSmartWalletFactory} from "../src/AidraSmartWalletFactory.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {_packValidationData} from "@account-abstraction/contracts/core/Helpers.sol";

contract EntryPointMock {
    uint256 public executions;

    function record() external {
        executions++;
    }
}

contract AidraSmartWalletCoreTest is Test {
    AidraSmartWalletFactory internal factory;
    AidraSmartWallet internal implementation;
    AidraSmartWallet internal wallet;

    address internal owner;
    uint256 internal ownerKey;
    address internal other = makeAddr("other");
    address internal registry = makeAddr("registry");
    address internal entryPoint;

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");

        implementation = new AidraSmartWallet();
        factory = new AidraSmartWalletFactory(address(implementation));

        vm.prank(owner);
        address account = factory.createSmartAccount();
        wallet = AidraSmartWallet(payable(account));

        entryPoint = wallet.entryPoint();

        vm.deal(account, 20 ether);
    }

    function _setRegistry(address registryAddr) internal {
        vm.prank(owner);
        wallet.setIntentRegistry(registryAddr);
    }

    function test_SetIntentRegistry_Succeeds() public {
        _setRegistry(registry);
        assertEq(address(wallet.s_intentRegistry()), registry);
    }

    function test_SetIntentRegistry_RevertsIfZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__IntentRegistryZeroAddress.selector);
        wallet.setIntentRegistry(address(0));
    }

    function test_SetIntentRegistry_RevertsIfAlreadySet() public {
        _setRegistry(registry);

        vm.prank(owner);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__IntentRegistryAlreadySet.selector);
        wallet.setIntentRegistry(makeAddr("registry2"));
    }

    function test_SetIntentRegistry_RevertsIfCallerUnauthorized() public {
        vm.prank(other);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__Unauthorized.selector);
        wallet.setIntentRegistry(registry);
    }

    function test_Execute_ByOwner() public {
        address payable recipient = payable(makeAddr("recipient"));

        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(owner);
        wallet.execute(recipient, 1 ether, "");

        assertEq(recipient.balance, recipientBalanceBefore + 1 ether);
        assertEq(address(wallet).balance, 19 ether);
    }

    function test_Execute_ByEntryPoint() public {
        address payable recipient = payable(makeAddr("entryRecipient"));

        vm.prank(entryPoint);
        wallet.execute(recipient, 1 ether, "");

        assertEq(recipient.balance, 1 ether);
        assertEq(address(wallet).balance, 19 ether);
    }

    function test_Execute_RevertsIfUnauthorized() public {
        vm.prank(other);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__Unauthorized.selector);
        wallet.execute(makeAddr("target"), 0, "");
    }

    function test_ExecuteBatch_ByOwner() public {
        AidraSmartWallet.Call[] memory calls = new AidraSmartWallet.Call[](2);
        calls[0] = AidraSmartWallet.Call({target: makeAddr("batchTarget1"), value: 1 ether, data: bytes("")});
        calls[1] = AidraSmartWallet.Call({target: makeAddr("batchTarget2"), value: 2 ether, data: bytes("")});

        vm.prank(owner);
        wallet.executeBatch(calls);

        assertEq(makeAddr("batchTarget1").balance, 1 ether);
        assertEq(makeAddr("batchTarget2").balance, 2 ether);
        assertEq(address(wallet).balance, 17 ether);
    }

    function test_ExecuteBatch_RevertsIfUnauthorized() public {
        AidraSmartWallet.Call[] memory calls = new AidraSmartWallet.Call[](1);
        calls[0] = AidraSmartWallet.Call({target: makeAddr("unauth"), value: 0, data: bytes("")});

        vm.prank(other);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__Unauthorized.selector);
        wallet.executeBatch(calls);
    }

    function test_ExecuteBatchIntentTransfer_RevertsIfRegistryNotSet() public {
        address[] memory recipients = new address[](1);
        recipients[0] = makeAddr("recipient1");
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.startPrank(registry);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__IntentRegistryNotSet.selector);
        wallet.executeBatchIntentTransfer(recipients, amounts);
        vm.stopPrank();
    }

    function test_ExecuteBatchIntentTransfer_RevertsIfCallerNotRegistry() public {
        _setRegistry(registry);

        address[] memory recipients = new address[](1);
        recipients[0] = makeAddr("recipient1");
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.startPrank(other);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__Unauthorized.selector);
        wallet.executeBatchIntentTransfer(recipients, amounts);
        vm.stopPrank();
    }

    function test_ExecuteBatchIntentTransfer_RevertsIfLengthMismatch() public {
        _setRegistry(registry);

        address[] memory recipients = new address[](2);
        recipients[0] = makeAddr("recipA");
        recipients[1] = makeAddr("recipB");
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.startPrank(registry);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__InvalidBatchInput.selector);
        wallet.executeBatchIntentTransfer(recipients, amounts);
        vm.stopPrank();
    }

    function test_ExecuteBatchIntentTransfer_RevertsIfNoRecipients() public {
        _setRegistry(registry);

        address[] memory recipients = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.startPrank(registry);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__InvalidBatchInput.selector);
        wallet.executeBatchIntentTransfer(recipients, amounts);
        vm.stopPrank();
    }

    function test_ExecuteBatchIntentTransfer_RevertsIfZeroRecipient() public {
        _setRegistry(registry);

        address[] memory recipients = new address[](1);
        recipients[0] = address(0);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.startPrank(registry);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__InvalidBatchInput.selector);
        wallet.executeBatchIntentTransfer(recipients, amounts);
        vm.stopPrank();
    }

    function test_ExecuteBatchIntentTransfer_RevertsIfZeroAmount() public {
        _setRegistry(registry);

        address[] memory recipients = new address[](1);
        recipients[0] = makeAddr("recipient1");
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        vm.startPrank(registry);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__InvalidBatchInput.selector);
        wallet.executeBatchIntentTransfer(recipients, amounts);
        vm.stopPrank();
    }

    function test_SetIntentRegistry_ByEntryPoint() public {
        address newRegistry = makeAddr("entryRegistry");

        vm.prank(entryPoint);
        wallet.setIntentRegistry(newRegistry);

        assertEq(address(wallet.s_intentRegistry()), newRegistry);
    }

    function test_Execute_ByEntryPoint_CallsTarget() public {
        EntryPointMock mock = new EntryPointMock();
        vm.prank(owner);
        wallet.setIntentRegistry(address(mock));

        bytes memory data = abi.encodeWithSignature("record()");

        vm.prank(entryPoint);
        wallet.execute(address(mock), 0, data);

        assertEq(mock.executions(), 1);
    }

    function test_ExecuteBatch_ByEntryPoint_CallsTargets() public {
        EntryPointMock mock = new EntryPointMock();
        vm.prank(owner);
        wallet.setIntentRegistry(address(mock));

        AidraSmartWallet.Call[] memory calls = new AidraSmartWallet.Call[](2);
        calls[0] = AidraSmartWallet.Call({target: address(mock), value: 0, data: abi.encodeWithSignature("record()")});
        calls[1] = AidraSmartWallet.Call({target: address(mock), value: 0, data: abi.encodeWithSignature("record()")});

        vm.prank(entryPoint);
        wallet.executeBatch(calls);

        assertEq(mock.executions(), 2);
    }

    function test_Execute_RevertsWhenTargetReverts() public {
        RevertingReceiver reverting = new RevertingReceiver();

        vm.prank(owner);
        vm.expectRevert(bytes("transfer failed"));
        wallet.execute(address(reverting), 0, "");
    }

    function test_ExecuteBatch_RevertsWhenInnerCallFails() public {
        RevertingReceiver reverting = new RevertingReceiver();

        AidraSmartWallet.Call[] memory calls = new AidraSmartWallet.Call[](1);
        calls[0] = AidraSmartWallet.Call({target: address(reverting), value: 0, data: bytes("")});

        vm.prank(owner);
        vm.expectRevert(bytes("transfer failed"));
        wallet.executeBatch(calls);
    }

    function test_ValidateUserOp_RevertsIfNotEntryPoint() public {
        PackedUserOperation memory userOp;
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__NotFromEntryPoint.selector);
        wallet.validateUserOp(userOp, bytes32(0), 0);
    }

    function test_ValidateUserOp_ReturnsFailingValidationDataOnBadSignature() public {
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(wallet),
            nonce: 0,
            initCode: bytes(""),
            callData: bytes(""),
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: bytes(""),
            signature: DUMMY_SIG
        });

        vm.prank(entryPoint);
        uint256 validationData = wallet.validateUserOp(userOp, keccak256("bad"), 0);

        assertEq(validationData, _packValidationData(true, 0, 0));
    }

    function test_ValidateUserOp_ReturnsFailingValidationDataWhenSignerNotOwner() public {
        (, uint256 attackerKey) = makeAddrAndKey("attacker");
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(wallet),
            nonce: 0,
            initCode: bytes(""),
            callData: bytes(""),
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: bytes(""),
            signature: _signatureFrom(attackerKey, keccak256("op"))
        });

        vm.prank(entryPoint);
        uint256 validationData = wallet.validateUserOp(userOp, keccak256("op"), 0);

        assertEq(validationData, _packValidationData(true, 0, 0));
    }

    function test_ValidateUserOp_SucceedsWhenSignedByOwner() public {
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(wallet),
            nonce: 0,
            initCode: bytes(""),
            callData: bytes(""),
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: bytes(""),
            signature: _signatureFrom(ownerKey, keccak256("good"))
        });

        vm.prank(entryPoint);
        uint256 validationData = wallet.validateUserOp(userOp, keccak256("good"), 1 ether);

        assertEq(validationData, _packValidationData(false, 0, 0));
    }

    function test_OnlyEntryPointRevertsForUnauthorizedCaller() public {
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__NotFromEntryPoint.selector);
        vm.prank(owner);
        wallet.validateUserOp(
            PackedUserOperation({
                sender: address(wallet),
                nonce: 0,
                initCode: bytes(""),
                callData: bytes(""),
                accountGasLimits: bytes32(0),
                preVerificationGas: 0,
                gasFees: bytes32(0),
                paymasterAndData: bytes(""),
                signature: DUMMY_SIG
            }),
            keccak256(""),
            0
        );
    }

    bytes constant DUMMY_SIG = hex"1b";

    function _signatureFrom(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_ExecuteBatchIntentTransfer_RevertsIfTransferFails() public {
        _setRegistry(registry);

        RevertingReceiver revertingRecipient = new RevertingReceiver();

        address[] memory recipients = new address[](1);
        recipients[0] = address(revertingRecipient);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.startPrank(registry);
        vm.expectRevert(
            abi.encodeWithSelector(
                AidraSmartWallet.AidraSmartWallet__TransferFailed.selector, address(revertingRecipient), 1 ether
            )
        );
        wallet.executeBatchIntentTransfer(recipients, amounts);
        vm.stopPrank();
    }

    function test_ExecuteBatchIntentTransfer_Succeeds() public {
        _setRegistry(registry);

        address payable recipient1 = payable(makeAddr("recipient1"));
        address payable recipient2 = payable(makeAddr("recipient2"));

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        vm.startPrank(registry);
        wallet.executeBatchIntentTransfer(recipients, amounts);
        vm.stopPrank();

        assertEq(recipient1.balance, 1 ether);
        assertEq(recipient2.balance, 2 ether);
        assertEq(address(wallet).balance, 17 ether);
    }
}

contract RevertingReceiver {
    receive() external payable {
        revert("transfer failed");
    }
}
