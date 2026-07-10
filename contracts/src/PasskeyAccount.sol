// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseAccount} from "./BaseAccount.sol";
import {PackedUserOperation} from "./interfaces/IAccount.sol";
import {WebAuthn} from "@openzeppelin/contracts/utils/cryptography/WebAuthn.sol";

/// @title PasskeyAccount
/// @notice ERC-4337 smart wallet (V3) — auth by DEVICE/BIOMETRICS (WebAuthn passkeys, P-256).
/// @dev Third auth scheme on the same BaseAccount Template Method (V1 = possession/secp256k1,
///      V2 = knowledge/secp256k1, V3 = device/secp256r1). Only `_validateSignature` and
///      `_authorizedAdmin` change — everything else (validation flow, prefund, execute) is inherited.
///
///      The signing key is a P-256 (secp256r1) key pair generated and held by the authenticator
///      (Secure Enclave / TPM / security key); the PRIVATE key never leaves the device. On-chain we
///      store only the PUBLIC key coordinates (x, y). A valid UserOp signature is a WebAuthn
///      assertion produced by `navigator.credentials.get()` over `userOpHash`.
///
///      SIGNATURE FORMAT: `userOp.signature` is the ABI-encoding of a `WebAuthn.WebAuthnAuth`
///      struct (r, s, challengeIndex, typeIndex, authenticatorData, clientDataJSON). The WebAuthn
///      protocol does NOT sign `userOpHash` directly: it signs
///      `sha256(authenticatorData || sha256(clientDataJSON))`, and `userOpHash` appears (base64url
///      encoded) as the `challenge` field INSIDE `clientDataJSON`. All of this parsing + the P-256
///      check is delegated to OpenZeppelin's audited `WebAuthn`/`P256` libraries.
///
///      P-256 VERIFICATION: `P256.verify` (called by `WebAuthn.verify`) uses the EIP-7951 precompile
///      at `0x100` when present (live on Sepolia post-Fusaka, ~6900 gas) and falls back to a pure
///      Solidity implementation otherwise — so unit tests pass on a local EVM without the precompile.
///      Signature malleability (low-s, `s <= N/2`) is enforced inside the library.
contract PasskeyAccount is BaseAccount {
    /// @dev secp256r1 public-key coordinates. Immutable: baked into the bytecode (no SLOAD during
    ///      validation), and — being constructor args — part of the CREATE2 init-code hash, so the
    ///      counterfactual address is a function of the passkey (see AccountFactory).
    bytes32 private immutable i_pubKeyX;
    bytes32 private immutable i_pubKeyY;

    event PasskeyAccountInitialized(address indexed entryPoint, bytes32 pubKeyX, bytes32 pubKeyY);

    /// @param _entryPoint EntryPoint address (0x4337...108 on Sepolia)
    /// @param _x          P-256 public key X coordinate (from the WebAuthn credential)
    /// @param _y          P-256 public key Y coordinate
    constructor(address _entryPoint, bytes32 _x, bytes32 _y) BaseAccount(_entryPoint) {
        i_pubKeyX = _x;
        i_pubKeyY = _y;
        emit PasskeyAccountInitialized(_entryPoint, _x, _y);
    }

    /// @inheritdoc BaseAccount
    /// @dev Decode the WebAuthn assertion from `userOp.signature`, then verify it against the stored
    ///      public key with `userOpHash` as the expected challenge. Returns 1 (never reverts) on any
    ///      malformed/invalid signature — the OZ libraries are written not to revert on bad input.
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        override
        returns (uint256)
    {
        (bool ok, WebAuthn.WebAuthnAuth calldata auth) = WebAuthn.tryDecodeAuth(userOp.signature);
        if (!ok) {
            return SIG_VALIDATION_FAILED;
        }
        // challenge = the raw 32 bytes of userOpHash; WebAuthn.verify base64url-encodes it and
        // checks it against the `challenge` field of clientDataJSON (binding the signature to THIS op).
        bool valid = WebAuthn.verify(bytes.concat(userOpHash), auth, i_pubKeyX, i_pubKeyY);
        return valid ? SIG_VALIDATION_SUCCESS : SIG_VALIDATION_FAILED;
    }

    /// @inheritdoc BaseAccount
    /// @dev A P-256 public key has no corresponding EVM address, so there is no key that could sign
    ///      an Ethereum transaction to drive the account directly. Direct (non-EntryPoint) execution
    ///      is therefore disabled by design: every action flows through a validated UserOp.
    function _authorizedAdmin() internal pure override returns (address) {
        return address(0);
    }

    /// @notice The secp256r1 public key that authorizes this account.
    function pubKey() external view returns (bytes32 x, bytes32 y) {
        return (i_pubKeyX, i_pubKeyY);
    }
}
