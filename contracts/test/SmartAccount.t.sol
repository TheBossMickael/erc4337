// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {PackedUserOperation} from "../src/interfaces/IAccount.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {MockEntryPoint} from "./mocks/MockEntryPoint.sol";

/// @title SmartAccountTest — unit tests for SmartAccount (local EVM, instant)
/// @dev We play the role of the EntryPoint through MockEntryPoint (vm.prank).
contract SmartAccountTest is Test {
    SmartAccount internal account;
    MockEntryPoint internal entryPoint;

    // Test private key for the owner. vm.addr derives its address.
    uint256 internal constant OWNER_KEY = 0xA11CE;
    address internal owner;

    // An arbitrary target to test execute().
    address internal constant TARGET = address(0xBEEF);

    function setUp() public {
        owner = vm.addr(OWNER_KEY);
        entryPoint = new MockEntryPoint();
        account = new SmartAccount(address(entryPoint), owner);
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER: sign a UserOp
    //////////////////////////////////////////////////////////////*/

    /// @dev Builds a UserOp whose signature is produced with `key`.
    ///      We reproduce EXACTLY what the contract does: we sign
    ///      toEthSignedMessageHash(userOpHash) (personal_sign convention).
    function _userOpSignedBy(bytes32 userOpHash, uint256 key)
        internal
        pure
        returns (PackedUserOperation memory userOp)
    {
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        // Expected ECDSA format: r (32) | s (32) | v (1) = 65 bytes.
        userOp.signature = abi.encodePacked(r, s, v);
        // The other fields stay zero: unused by validateUserOp.
    }

    /*//////////////////////////////////////////////////////////////
                                VALIDATION
    //////////////////////////////////////////////////////////////*/

    function test_validateUserOp_validSignature_returnsZero() public {
        bytes32 userOpHash = keccak256("some userop");
        PackedUserOperation memory userOp = _userOpSignedBy(userOpHash, OWNER_KEY);

        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 0, "owner signature => 0");
    }

    function test_validateUserOp_wrongSigner_returnsOne() public {
        bytes32 userOpHash = keccak256("some userop");
        uint256 attackerKey = 0xBAD;
        PackedUserOperation memory userOp = _userOpSignedBy(userOpHash, attackerKey);

        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 1, "bad signature => 1, without reverting");
    }

    function test_validateUserOp_malformedSignature_returnsOneNoRevert() public {
        bytes32 userOpHash = keccak256("some userop");
        PackedUserOperation memory userOp;
        userOp.signature = hex"1234"; // signature too short / invalid

        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        // ECDSA.tryRecover returns an error without reverting => we must get 1.
        assertEq(validationData, 1, "malformed signature => 1, never reverts");
    }

    function test_validateUserOp_notFromEntryPoint_reverts() public {
        bytes32 userOpHash = keccak256("some userop");
        PackedUserOperation memory userOp = _userOpSignedBy(userOpHash, OWNER_KEY);

        vm.prank(address(0xDEAD)); // anyone except the EntryPoint
        vm.expectRevert(SmartAccount.SmartAccount__NotFromEntryPoint.selector);
        account.validateUserOp(userOp, userOpHash, 0);
    }

    function test_validateUserOp_paysPrefund() public {
        bytes32 userOpHash = keccak256("some userop");
        PackedUserOperation memory userOp = _userOpSignedBy(userOpHash, OWNER_KEY);

        // The account must hold ETH to be able to advance the prefund.
        vm.deal(address(account), 1 ether);
        uint256 missing = 0.3 ether;

        vm.prank(address(entryPoint));
        account.validateUserOp(userOp, userOpHash, missing);

        // The mock credits the sender's deposit (the account) on reception.
        assertEq(entryPoint.balanceOf(address(account)), missing, "prefund received by the EntryPoint");
    }

    /*//////////////////////////////////////////////////////////////
                                EXECUTION
    //////////////////////////////////////////////////////////////*/

    function test_execute_transfersEth() public {
        vm.deal(address(account), 1 ether);

        vm.prank(address(entryPoint));
        account.execute(TARGET, 0.5 ether, "");

        assertEq(TARGET.balance, 0.5 ether, "ETH transferred to the target");
    }

    function test_execute_byOwner_isAllowed() public {
        vm.deal(address(account), 1 ether);

        vm.prank(owner);
        account.execute(TARGET, 0.1 ether, "");

        assertEq(TARGET.balance, 0.1 ether, "owner can drive the account directly");
    }

    function test_execute_notFromEntryPointOrOwner_reverts() public {
        vm.deal(address(account), 1 ether);

        vm.prank(address(0xDEAD));
        vm.expectRevert(SmartAccount.SmartAccount__NotFromEntryPointOrOwner.selector);
        account.execute(TARGET, 0.1 ether, "");
    }

    function test_executeBatch_runsAllCalls() public {
        vm.deal(address(account), 1 ether);

        address[] memory dest = new address[](2);
        uint256[] memory value = new uint256[](2);
        bytes[] memory func = new bytes[](2);
        dest[0] = address(0xAAA1);
        dest[1] = address(0xAAA2);
        value[0] = 0.1 ether;
        value[1] = 0.2 ether;
        func[0] = "";
        func[1] = "";

        vm.prank(address(entryPoint));
        account.executeBatch(dest, value, func);

        assertEq(address(0xAAA1).balance, 0.1 ether);
        assertEq(address(0xAAA2).balance, 0.2 ether);
    }

    function test_executeBatch_lengthMismatch_reverts() public {
        address[] memory dest = new address[](2);
        uint256[] memory value = new uint256[](1);
        bytes[] memory func = new bytes[](2);

        vm.prank(address(entryPoint));
        vm.expectRevert(SmartAccount.SmartAccount__WrongArrayLengths.selector);
        account.executeBatch(dest, value, func);
    }

    /*//////////////////////////////////////////////////////////////
                              DEPOSIT & GETTERS
    //////////////////////////////////////////////////////////////*/

    function test_addDeposit_creditsEntryPoint() public {
        vm.deal(address(this), 1 ether);
        account.addDeposit{value: 0.4 ether}();
        assertEq(account.getDeposit(), 0.4 ether);
    }

    function test_getters() public view {
        assertEq(account.owner(), owner);
        assertEq(account.entryPoint(), address(entryPoint));
    }
}
