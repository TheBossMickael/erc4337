// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {PasskeyAccount} from "../src/PasskeyAccount.sol";
import {PackedUserOperation} from "../src/interfaces/IAccount.sol";
import {P256} from "@openzeppelin/contracts/utils/cryptography/P256.sol";
import {WebAuthnVector} from "./fixtures/WebAuthnVector.sol";

/// @title PasskeyForkTest — exercises the REAL secp256r1 precompile (EIP-7951 @ 0x100) on Sepolia.
/// @notice Run against a RECENT Sepolia fork (post-Fusaka, where 0x100 is live):
///   forge test --match-path test/Passkey.fork.t.sol --fork-url $SEPOLIA_RPC_URL -vvv
///
/// @dev The local unit tests (PasskeyAccount.t.sol) validate the same locked vector via OZ's
///      pure-Solidity P-256 fallback. What they CANNOT prove is that the on-chain precompile behaves
///      correctly — that is this file's job:
///        1. `P256.verifyNative` calls `0x100` directly and REVERTS if the precompile is absent, so a
///           `true` here is positive proof the precompile is live AND validates our vector.
///        2. The full PasskeyAccount.validateUserOp path returns 0 through the precompile.
///
///      The complete `handleOps + initCode` end-to-end (factory deploys the account inside the first
///      UserOp) is validated in the browser against the deployed Render URL: Foundry cannot produce a
///      fresh P-256 signature for the dynamic userOpHash (no P-256 signing cheatcode).
///
///      Without `--fork-url`, the EntryPoint address has no code and the tests are SKIPPED (onlyFork).
contract PasskeyForkTest is Test {
    /// @dev ERC-4337 v0.8 EntryPoint on Sepolia — used here only as a "are we on a fork?" sentinel.
    address internal constant ENTRYPOINT = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

    /// @dev Skips the test if the EntryPoint has no code (= we are not on a Sepolia fork).
    modifier onlyFork() {
        if (ENTRYPOINT.code.length == 0) {
            emit log("EntryPoint missing: test skipped (run with --fork-url $SEPOLIA_RPC_URL)");
            vm.skip(true);
            return;
        }
        _;
    }

    /// @notice The live `0x100` precompile validates our locked WebAuthn vector.
    function test_p256Precompile_validatesVector() public onlyFork {
        bool ok = P256.verifyNative(
            WebAuthnVector.message(),
            WebAuthnVector.SIG_R,
            WebAuthnVector.SIG_S,
            WebAuthnVector.PUBKEY_X,
            WebAuthnVector.PUBKEY_Y
        );
        assertTrue(ok, "real 0x100 precompile validates the P-256 signature");
    }

    /// @notice The full PasskeyAccount validation path returns 0 through the real precompile.
    function test_passkeyAccount_validateUserOp_throughPrecompile() public onlyFork {
        PasskeyAccount account = new PasskeyAccount(ENTRYPOINT, WebAuthnVector.PUBKEY_X, WebAuthnVector.PUBKEY_Y);

        PackedUserOperation memory userOp;
        userOp.signature = WebAuthnVector.signature();

        vm.prank(ENTRYPOINT);
        uint256 validationData = account.validateUserOp(userOp, WebAuthnVector.USER_OP_HASH, 0);

        assertEq(validationData, 0, "valid assertion => 0 via the on-chain precompile");
        console2.log("PasskeyAccount validated a WebAuthn assertion through the real P-256 precompile.");
    }
}
