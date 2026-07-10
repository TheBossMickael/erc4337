import { p256 } from '@noble/curves/p256';
import {
  bytesToHex,
  hexToBytes,
  numberToHex,
  encodeAbiParameters,
  type Hex,
} from 'viem';

/**
 * V3 — Authentication by DEVICE/BIOMETRICS (WebAuthn passkeys, P-256 / secp256r1).
 *
 * The signing key is generated and held by the authenticator (Secure Enclave / TPM / security key);
 * the PRIVATE key never leaves the device. We only ever handle the PUBLIC key (x, y) and per-assertion
 * signatures. This module has two halves:
 *   - PURE helpers (unit-tested against the locked vector in webauthn.test.ts): parsing + encoding.
 *   - BROWSER ceremonies (createPasskey / signAssertion): thin wrappers over `navigator.credentials`.
 *
 * The on-chain counterpart is PasskeyAccount + OZ's WebAuthn/P256 libraries. The signature we produce
 * MUST match what `WebAuthn.tryDecodeAuth` expects (see `encodeWebAuthnSignature`).
 */

/* ────────────────────────────── PURE HELPERS ────────────────────────────── */

/**
 * Extracts the secp256r1 public-key coordinates (x, y) from a P-256 public key.
 * Works both for a raw uncompressed point (`0x04 || x || y`, 65 bytes) and for a full SPKI DER
 * (what `getPublicKey()` returns) — the uncompressed point is always the trailing 65 bytes, so the
 * last 64 bytes are `x || y`.
 */
export function extractXY(pub: Uint8Array): { x: Hex; y: Hex } {
  if (pub.length < 64) {
    throw new Error('extractXY: public key too short');
  }
  return {
    x: bytesToHex(pub.slice(pub.length - 64, pub.length - 32)),
    y: bytesToHex(pub.slice(pub.length - 32)),
  };
}

/**
 * Parses a DER-encoded ECDSA signature (as produced by WebAuthn authenticators) into (r, s),
 * normalized to LOW-S. This normalization is mandatory: authenticators may return a high-s value,
 * but OZ's `P256` rejects `s > N/2` as malleable.
 */
export function parseDerSignature(der: Uint8Array): { r: Hex; s: Hex } {
  const sig = p256.Signature.fromDER(der).normalizeS();
  return { r: numberToHex(sig.r, { size: 32 }), s: numberToHex(sig.s, { size: 32 }) };
}

/**
 * Locates the byte offsets of the `"challenge":"` and `"type":"` fields in clientDataJSON. OZ's
 * `WebAuthn.verify` uses these indices to read the fields without fully parsing the JSON on-chain.
 */
export function webauthnIndices(clientDataJSON: string): { challengeIndex: number; typeIndex: number } {
  return {
    challengeIndex: clientDataJSON.indexOf('"challenge":"'),
    typeIndex: clientDataJSON.indexOf('"type":"'),
  };
}

/** The ABI parameter layout of a WebAuthn assertion, as a TOP-LEVEL tuple (see below). */
const WEBAUTHN_AUTH_PARAMS = [
  { type: 'bytes32' }, // r
  { type: 'bytes32' }, // s
  { type: 'uint256' }, // challengeIndex
  { type: 'uint256' }, // typeIndex
  { type: 'bytes' }, //   authenticatorData
  { type: 'string' }, //  clientDataJSON
] as const;

/**
 * Encodes a WebAuthn assertion as a `userOp.signature`.
 *
 * IMPORTANT: the 6 fields are encoded as a TOP-LEVEL tuple, NOT as a single `tuple` parameter. OZ's
 * `WebAuthn.tryDecodeAuth` reads the fields straight from the calldata start (`input.offset`); a
 * single-`tuple` encoding would prepend a 0x20 offset word and shift everything by 32 bytes, making
 * the decode fail. This mirrors `WebAuthnVector.signature()` on the Solidity side.
 */
export function encodeWebAuthnSignature(a: {
  r: Hex;
  s: Hex;
  challengeIndex: number;
  typeIndex: number;
  authenticatorData: Hex;
  clientDataJSON: string;
}): Hex {
  return encodeAbiParameters(WEBAUTHN_AUTH_PARAMS, [
    a.r,
    a.s,
    BigInt(a.challengeIndex),
    BigInt(a.typeIndex),
    a.authenticatorData,
    a.clientDataJSON,
  ]);
}

/* ────────────────────────────── BROWSER CEREMONIES ────────────────────────────── */

/**
 * Copies hex into a fresh Uint8Array backed by a plain ArrayBuffer, typed as `BufferSource`.
 * WebAuthn's `BufferSource` excludes `SharedArrayBuffer`, whereas viem's `hexToBytes` returns the
 * wider `Uint8Array<ArrayBufferLike>`. `new Uint8Array(length)` is always ArrayBuffer-backed, and the
 * `BufferSource` return annotation stays valid across TS lib versions (unlike `Uint8Array<ArrayBuffer>`).
 */
function bufferFromHex(hex: Hex): BufferSource {
  const bytes = hexToBytes(hex);
  const out = new Uint8Array(bytes.length);
  out.set(bytes);
  return out;
}

/** A passkey known to this browser: its credential id + the public key coordinates. */
export interface Passkey {
  credentialId: Hex;
  x: Hex;
  y: Hex;
}

/**
 * Registers a NEW passkey (`navigator.credentials.create`) and returns its id + public key (x, y).
 * The rp id is intentionally omitted so the browser uses the current effective domain (works on the
 * deployed HTTPS origin without hardcoding it; note WebAuthn requires a secure context).
 */
export async function createPasskey(userName = 'erc4337 passkey wallet'): Promise<Passkey> {
  const userId = crypto.getRandomValues(new Uint8Array(16));
  const credential = (await navigator.credentials.create({
    publicKey: {
      challenge: crypto.getRandomValues(new Uint8Array(32)), // registration challenge (unused on-chain)
      rp: { name: 'ERC-4337 Passkey Wallet' },
      user: { id: userId, name: userName, displayName: userName },
      pubKeyCredParams: [{ type: 'public-key', alg: -7 }], // -7 = ES256 (P-256)
      authenticatorSelection: { userVerification: 'required', residentKey: 'preferred' },
      timeout: 60_000,
    },
  })) as PublicKeyCredential | null;

  if (!credential) {
    throw new Error('Passkey registration was cancelled');
  }
  const response = credential.response as AuthenticatorAttestationResponse;
  const spki = response.getPublicKey();
  if (!spki) {
    throw new Error('Could not read the passkey public key (getPublicKey unsupported)');
  }
  const { x, y } = extractXY(new Uint8Array(spki));
  return { credentialId: bytesToHex(new Uint8Array(credential.rawId)), x, y };
}

/**
 * Signs `challenge` (the raw 32-byte userOpHash) with an existing passkey and returns the encoded
 * `userOp.signature`. Requires user verification (UV=1), matching PasskeyAccount's on-chain check.
 */
export async function signAssertion(challenge: Hex, credentialId: Hex): Promise<Hex> {
  const assertion = (await navigator.credentials.get({
    publicKey: {
      challenge: bufferFromHex(challenge),
      allowCredentials: [{ id: bufferFromHex(credentialId), type: 'public-key' }],
      userVerification: 'required',
      timeout: 60_000,
    },
  })) as PublicKeyCredential | null;

  if (!assertion) {
    throw new Error('Passkey signature was cancelled');
  }
  const response = assertion.response as AuthenticatorAssertionResponse;
  const authenticatorData = new Uint8Array(response.authenticatorData);
  const clientDataJSON = new TextDecoder().decode(response.clientDataJSON);
  const { r, s } = parseDerSignature(new Uint8Array(response.signature));
  const { challengeIndex, typeIndex } = webauthnIndices(clientDataJSON);

  return encodeWebAuthnSignature({
    r,
    s,
    challengeIndex,
    typeIndex,
    authenticatorData: bytesToHex(authenticatorData),
    clientDataJSON,
  });
}
