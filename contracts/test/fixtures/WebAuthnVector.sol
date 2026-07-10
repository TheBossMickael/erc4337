// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title WebAuthnVector — a single LOCKED WebAuthn (P-256 / secp256r1) assertion vector.
/// @notice Shared source of truth for the Solidity tests (unit + fork). Generated deterministically
///         by frontend/scripts/gen-webauthn-vector.mjs (fixed P-256 key + fixed challenge). The SAME
///         values are cross-checked in frontend/src/lib/webauthn.test.ts — any change to the signature
///         format/derivation breaks all of them at once. Regenerate: `npm run gen:vector` (in frontend).
library WebAuthnVector {
    bytes32 internal constant PUBKEY_X = 0x60fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb6;
    bytes32 internal constant PUBKEY_Y = 0x7903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299;
    /// @dev The 32-byte "userOpHash" the passkey signed over (the WebAuthn challenge).
    bytes32 internal constant USER_OP_HASH = 0x0a3e26d20c77ce020cc294bb50f3144fd3d85b4cf1f3578f45ba9a1067c6ff26;
    bytes32 internal constant SIG_R = 0x355556da782fe9055335e0bfd6dbb648ea8a41fb9f2dd49eb34e30205a271b13;
    bytes32 internal constant SIG_S = 0x4ae9f621ec076527f4daa5a447da8f6c727aea134e187820d69f7db7278f9711;
    uint256 internal constant CHALLENGE_INDEX = 23;
    uint256 internal constant TYPE_INDEX = 1;
    bytes internal constant AUTHENTICATOR_DATA = hex"e03670c58143d03af056aab89fcb3e896846b3dc67e5a17a7bc2bf11029166170500000000";
    string internal constant CLIENT_DATA_JSON =
        '{"type":"webauthn.get","challenge":"Cj4m0gx3zgIMwpS7UPMUT9PYW0zx81ePRbqaEGfG_yY","origin":"https://erc4337.onrender.com","crossOrigin":false}';

    /// @dev Encodes the assertion as a `userOp.signature`. IMPORTANT: encode the 6 fields as a
    ///      TOP-LEVEL tuple, NOT `abi.encode(struct)` — the latter prepends a 0x20 offset word that
    ///      OZ's `WebAuthn.tryDecodeAuth` (which reads fields straight from `input.offset`) does not
    ///      expect. The frontend must mirror this exactly (viem: 6 params, not a single `tuple`).
    function signature() internal pure returns (bytes memory) {
        return abi.encode(SIG_R, SIG_S, CHALLENGE_INDEX, TYPE_INDEX, AUTHENTICATOR_DATA, CLIENT_DATA_JSON);
    }

    /// @dev The 32-byte message actually signed by P-256: sha256(authenticatorData ‖ sha256(clientDataJSON)).
    ///      `sha256` is a builtin (precompile 0x02, always available) and treated as pure by the compiler.
    function message() internal pure returns (bytes32) {
        return sha256(abi.encodePacked(AUTHENTICATOR_DATA, sha256(bytes(CLIENT_DATA_JSON))));
    }
}
