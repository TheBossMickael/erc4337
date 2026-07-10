// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PasskeyAccount} from "../src/PasskeyAccount.sol";
import {BaseAccount} from "../src/BaseAccount.sol";
import {PackedUserOperation} from "../src/interfaces/IAccount.sol";
import {MockEntryPoint} from "./mocks/MockEntryPoint.sol";
import {WebAuthnVector} from "./fixtures/WebAuthnVector.sol";

/// @title PasskeyAccountTest — unit tests for PasskeyAccount (local EVM, instant).
/// @dev We play the EntryPoint via MockEntryPoint (vm.prank). Foundry has NO P-256 signing cheatcode,
///      so the valid signature is a LOCKED WebAuthn vector (see WebAuthnVector fixture), generated
///      off-chain by frontend/scripts/gen-webauthn-vector.mjs and cross-checked in
///      frontend/src/lib/webauthn.test.ts — the V3 analog of V2's demo-vector cross-check.
///
///      P-256 verification runs via OZ's `P256.verify`, which uses the `0x100` precompile when present
///      and a pure-Solidity fallback otherwise — so this suite is green on a local EVM WITHOUT the
///      precompile. The real precompile path is exercised separately in Passkey.fork.t.sol.
contract PasskeyAccountTest is Test {
    PasskeyAccount internal account;
    MockEntryPoint internal entryPoint;

    address internal constant TARGET = address(0xBEEF);

    function setUp() public {
        entryPoint = new MockEntryPoint();
        account = new PasskeyAccount(address(entryPoint), WebAuthnVector.PUBKEY_X, WebAuthnVector.PUBKEY_Y);
    }

    /*//////////////////////////////////////////////////////////////
                                VALIDATION
    //////////////////////////////////////////////////////////////*/

    function test_validateUserOp_validAssertion_returnsZero() public {
        PackedUserOperation memory userOp;
        userOp.signature = WebAuthnVector.signature();

        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, WebAuthnVector.USER_OP_HASH, 0);

        assertEq(validationData, 0, "valid WebAuthn assertion over userOpHash => 0");
    }

    function test_validateUserOp_wrongChallenge_returnsOne() public {
        // Same signature, but a DIFFERENT userOpHash than the one embedded in clientDataJSON.
        PackedUserOperation memory userOp;
        userOp.signature = WebAuthnVector.signature();

        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, keccak256("some other userop"), 0);

        assertEq(validationData, 1, "challenge mismatch => 1 (signature not bound to this op)");
    }

    function test_validateUserOp_wrongPubKey_returnsOne() public {
        // An account for a DIFFERENT passkey must reject this assertion. Flipping one bit of X moves
        // the point off the curve => P256 rejects it (isValidPublicKey false) => 1, no revert.
        PasskeyAccount other = new PasskeyAccount(
            address(entryPoint), bytes32(uint256(WebAuthnVector.PUBKEY_X) ^ 1), WebAuthnVector.PUBKEY_Y
        );

        PackedUserOperation memory userOp;
        userOp.signature = WebAuthnVector.signature();

        vm.prank(address(entryPoint));
        assertEq(other.validateUserOp(userOp, WebAuthnVector.USER_OP_HASH, 0), 1, "wrong public key => 1");
    }

    function test_validateUserOp_malformedSignature_returnsOneNoRevert() public {
        PackedUserOperation memory userOp;
        userOp.signature = hex"1234"; // too short to decode a WebAuthnAuth

        vm.prank(address(entryPoint));
        assertEq(account.validateUserOp(userOp, WebAuthnVector.USER_OP_HASH, 0), 1, "malformed => 1, never reverts");
    }

    function test_validateUserOp_emptySignature_returnsOneNoRevert() public {
        PackedUserOperation memory userOp; // signature == ""

        vm.prank(address(entryPoint));
        assertEq(account.validateUserOp(userOp, WebAuthnVector.USER_OP_HASH, 0), 1, "empty => 1, never reverts");
    }

    function test_validateUserOp_notFromEntryPoint_reverts() public {
        PackedUserOperation memory userOp;
        userOp.signature = WebAuthnVector.signature();

        vm.prank(address(0xDEAD));
        vm.expectRevert(BaseAccount.BaseAccount__NotFromEntryPoint.selector);
        account.validateUserOp(userOp, WebAuthnVector.USER_OP_HASH, 0);
    }

    function test_validateUserOp_paysPrefund() public {
        PackedUserOperation memory userOp;
        userOp.signature = WebAuthnVector.signature();

        vm.deal(address(account), 1 ether);
        uint256 missing = 0.3 ether;

        vm.prank(address(entryPoint));
        account.validateUserOp(userOp, WebAuthnVector.USER_OP_HASH, missing);

        assertEq(entryPoint.balanceOf(address(account)), missing, "prefund received by the EntryPoint");
    }

    /*//////////////////////////////////////////////////////////////
                                EXECUTION
    //////////////////////////////////////////////////////////////*/

    function test_execute_fromEntryPoint_transfersEth() public {
        vm.deal(address(account), 1 ether);

        vm.prank(address(entryPoint));
        account.execute(TARGET, 0.5 ether, "");

        assertEq(TARGET.balance, 0.5 ether, "ETH transferred to the target");
    }

    /// @dev No EVM address corresponds to a P-256 key (admin == address(0)), so ONLY the EntryPoint
    ///      can drive the account. Any external caller is rejected.
    function test_execute_notFromEntryPoint_reverts() public {
        vm.deal(address(account), 1 ether);

        vm.prank(address(0xDEAD));
        vm.expectRevert(BaseAccount.BaseAccount__NotFromEntryPointOrOwner.selector);
        account.execute(TARGET, 0.1 ether, "");
    }

    /*//////////////////////////////////////////////////////////////
                                 GETTERS
    //////////////////////////////////////////////////////////////*/

    function test_getters() public view {
        (bytes32 x, bytes32 y) = account.pubKey();
        assertEq(x, WebAuthnVector.PUBKEY_X, "pubKeyX");
        assertEq(y, WebAuthnVector.PUBKEY_Y, "pubKeyY");
        assertEq(account.entryPoint(), address(entryPoint), "entryPoint");
    }
}
