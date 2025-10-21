// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Test} from "forge-std/Test.sol";
import {AidraSmartWallet} from "../src/AidraSmartWallet.sol";
import {AidraSmartWalletFactory} from "../src/AidraSmartWalletFactory.sol";
import {AidraIntentRegistry} from "../src/AidraIntentRegistry.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {_packValidationData} from "@account-abstraction/contracts/core/Helpers.sol";

contract EntryPointMock {
    uint256 public executions;

    function record() external {
        executions++;
    }
}

contract WalletTests is Test {
    AidraSmartWalletFactory internal factory;
    AidraSmartWallet internal implementation;
    AidraSmartWallet internal smartWallet;

    address internal owner;
    uint256 internal ownerKey;
    address internal other = makeAddr("other");
    address internal registry = makeAddr("registry");
    address internal entryPoint;

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");

        implementation = new AidraSmartWallet(registry);
        factory = new AidraSmartWalletFactory(address(implementation));

        vm.prank(owner);
        address account = factory.createSmartAccount(owner);
        smartWallet = AidraSmartWallet(payable(account));

        entryPoint = smartWallet.entryPoint();

        vm.deal(account, 20 ether);
    }


    function test_Execute_ByOwner() public {
        address payable recipient = payable(makeAddr("recipient"));

        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(owner);
        smartWallet.execute(recipient, 1 ether, "");

        assertEq(recipient.balance, recipientBalanceBefore + 1 ether);
        assertEq(address(smartWallet).balance, 19 ether);
    }

    function test_Execute_ByEntryPoint() public {
        address payable recipient = payable(makeAddr("entryRecipient"));

        vm.prank(entryPoint);
        smartWallet.execute(recipient, 1 ether, "");

        assertEq(recipient.balance, 1 ether);
        assertEq(address(smartWallet).balance, 19 ether);
    }

    function test_Execute_RevertsIfUnauthorized() public {
        vm.prank(other);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__Unauthorized.selector);
        smartWallet.execute(makeAddr("target"), 0, "");
    }

    function test_ExecuteBatch_ByOwner() public {
        AidraSmartWallet.Call[] memory calls = new AidraSmartWallet.Call[](2);
        calls[0] = AidraSmartWallet.Call({target: makeAddr("batchTarget1"), value: 1 ether, data: bytes("")});
        calls[1] = AidraSmartWallet.Call({target: makeAddr("batchTarget2"), value: 2 ether, data: bytes("")});

        vm.prank(owner);
        smartWallet.executeBatch(calls);

        assertEq(makeAddr("batchTarget1").balance, 1 ether);
        assertEq(makeAddr("batchTarget2").balance, 2 ether);
        assertEq(address(smartWallet).balance, 17 ether);
    }

    function test_ExecuteBatch_RevertsIfUnauthorized() public {
        AidraSmartWallet.Call[] memory calls = new AidraSmartWallet.Call[](1);
        calls[0] = AidraSmartWallet.Call({target: makeAddr("unauth"), value: 0, data: bytes("")});

        vm.prank(other);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__Unauthorized.selector);
        smartWallet.executeBatch(calls);
    }

    function test_ExecuteBatchIntentTransfer_RevertsIfLengthMismatch() public {
        address[] memory recipients = new address[](2);
        recipients[0] = makeAddr("recipA");
        recipients[1] = makeAddr("recipB");
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.startPrank(registry);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__InvalidBatchInput.selector);
        smartWallet.executeBatchIntentTransfer(recipients, amounts, bytes32(0), 0, false);
        vm.stopPrank();
    }

    function test_ExecuteBatchIntentTransfer_RevertsIfNoRecipients() public {
        address[] memory recipients = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.startPrank(registry);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__InvalidBatchInput.selector);
        smartWallet.executeBatchIntentTransfer(recipients, amounts, bytes32(0), 0, false);
        vm.stopPrank();
    }

    function test_ExecuteBatchIntentTransfer_RevertsIfZeroRecipient() public {
        address[] memory recipients = new address[](1);
        recipients[0] = address(0);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.startPrank(registry);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__InvalidBatchInput.selector);
        smartWallet.executeBatchIntentTransfer(recipients, amounts, bytes32(0), 0, false);
        vm.stopPrank();
    }

    function test_ExecuteBatchIntentTransfer_RevertsIfZeroAmount() public {
        address[] memory recipients = new address[](1);
        recipients[0] = makeAddr("recipient1");
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        vm.startPrank(registry);
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__InvalidBatchInput.selector);
        smartWallet.executeBatchIntentTransfer(recipients, amounts, bytes32(0), 0, false);
        vm.stopPrank();
    }


    function test_Execute_ByEntryPoint_CallsTarget() public {
        EntryPointMock mock = new EntryPointMock();
        // Note: Registry is already set during initialization

        bytes memory data = abi.encodeWithSignature("record()");

        vm.prank(entryPoint);
        smartWallet.execute(address(mock), 0, data);

        assertEq(mock.executions(), 1);
    }

    function test_ExecuteBatch_ByEntryPoint_CallsTargets() public {
        EntryPointMock mock = new EntryPointMock();
        // Note: Registry is already set during initialization

        AidraSmartWallet.Call[] memory calls = new AidraSmartWallet.Call[](2);
        calls[0] = AidraSmartWallet.Call({target: address(mock), value: 0, data: abi.encodeWithSignature("record()")});
        calls[1] = AidraSmartWallet.Call({target: address(mock), value: 0, data: abi.encodeWithSignature("record()")});

        vm.prank(entryPoint);
        smartWallet.executeBatch(calls);

        assertEq(mock.executions(), 2);
    }

    function test_Execute_RevertsWhenTargetReverts() public {
        RevertingReceiver reverting = new RevertingReceiver();

        vm.prank(owner);
        vm.expectRevert(bytes("transfer failed"));
        smartWallet.execute(address(reverting), 0, "");
    }

    function test_ExecuteBatch_RevertsWhenInnerCallFails() public {
        RevertingReceiver reverting = new RevertingReceiver();

        AidraSmartWallet.Call[] memory calls = new AidraSmartWallet.Call[](1);
        calls[0] = AidraSmartWallet.Call({target: address(reverting), value: 0, data: bytes("")});

        vm.prank(owner);
        vm.expectRevert(bytes("transfer failed"));
        smartWallet.executeBatch(calls);
    }

    function test_ValidateUserOp_RevertsIfNotEntryPoint() public {
        PackedUserOperation memory userOp;
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__NotFromEntryPoint.selector);
        smartWallet.validateUserOp(userOp, bytes32(0), 0);
    }

    bytes constant DUMMY_SIG = hex"1b";

    function _signatureFrom(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_ValidateUserOp_ReturnsFailingValidationDataOnBadSignature() public {
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(smartWallet),
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
        uint256 validationData = smartWallet.validateUserOp(userOp, keccak256("bad"), 0);

        assertEq(validationData, _packValidationData(true, 0, 0));
    }

    function test_ValidateUserOp_ReturnsFailingValidationDataWhenSignerNotOwner() public {
        (, uint256 attackerKey) = makeAddrAndKey("attacker");
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(smartWallet),
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
        uint256 validationData = smartWallet.validateUserOp(userOp, keccak256("op"), 0);

        assertEq(validationData, _packValidationData(true, 0, 0));
    }

    function test_ValidateUserOp_SucceedsWhenSignedByOwner() public {
        // Generate signature over the EIP-191 prefixed hash like the contract does
        bytes32 userOpHash = keccak256("good");
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(smartWallet),
            nonce: 0,
            initCode: bytes(""),
            callData: bytes(""),
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: bytes(""),
            signature: _signatureFrom(ownerKey, ethSignedMessageHash)
        });

        vm.prank(entryPoint);
        uint256 validationData = smartWallet.validateUserOp(userOp, userOpHash, 1 ether);

        assertEq(validationData, _packValidationData(false, 0, 0));
    }

    function test_OnlyEntryPointRevertsForUnauthorizedCaller() public {
        vm.expectRevert(AidraSmartWallet.AidraSmartWallet__NotFromEntryPoint.selector);
        vm.prank(owner);
        smartWallet.validateUserOp(
            PackedUserOperation({
                sender: address(smartWallet),
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

    function test_ExecuteBatchIntentTransfer_RevertsIfTransferFails() public {
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
        smartWallet.executeBatchIntentTransfer(recipients, amounts, bytes32(0), 0, true);
        vm.stopPrank();
    }

    function test_ExecuteBatchIntentTransfer_Succeeds() public {
        address payable recipient1 = payable(makeAddr("recipient1"));
        address payable recipient2 = payable(makeAddr("recipient2"));

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        vm.startPrank(registry);
        smartWallet.executeBatchIntentTransfer(recipients, amounts, bytes32(0), 0, false);
        vm.stopPrank();

        assertEq(recipient1.balance, 1 ether);
        assertEq(recipient2.balance, 2 ether);
        assertEq(address(smartWallet).balance, 17 ether);
    }
}

contract RevertingReceiver {
    receive() external payable {
        revert("transfer failed");
    }
}
