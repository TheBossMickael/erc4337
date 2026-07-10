// Generates a DETERMINISTIC WebAuthn (P-256 / secp256r1) authentication-assertion vector.
//
// The exact same vector is hardcoded in two places and cross-checked, so that any change to the
// signature format or parsing breaks BOTH at once (the V3 analog of V2's demo-vector cross-check):
//   - contracts/test/PasskeyAccount.t.sol   (on-chain validation, via OZ WebAuthn/P256 fallback)
//   - frontend/src/lib/webauthn.test.ts      (off-chain parsing: SPKI -> (x,y), DER -> (r,s), b64url)
//
// It reproduces EXACTLY what a browser authenticator produces during `navigator.credentials.get()`:
//   message = sha256( authenticatorData || sha256(clientDataJSON) )
//   signature = ECDSA-P256(privKey, message), low-s normalized
// with the WebAuthn `challenge` (= our userOpHash) base64url-encoded inside clientDataJSON.
//
// Foundry has no P-256 signing cheatcode, so we pre-compute the vector here once and lock it.
//
// Run:  cd frontend && npm install && node scripts/gen-webauthn-vector.mjs
import { createHash } from 'node:crypto';
import { p256 } from '@noble/curves/p256';

const sha256 = (buf) => createHash('sha256').update(buf).digest();
const to32 = (bi) => '0x' + bi.toString(16).padStart(64, '0');
const hex = (u8) => '0x' + Buffer.from(u8).toString('hex');

// ── Fixed inputs — change nothing here and the vector is identical on every run ──────────────
// A valid secp256r1 scalar (0 < k < n). Arbitrary but fixed.
const PRIVATE_KEY = 'c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721';
const RP_ID = 'erc4337.onrender.com'; // NOTE: OZ WebAuthn does NOT check rpIdHash/origin, cosmetic here
const ORIGIN = 'https://erc4337.onrender.com';
// The 32-byte "userOpHash" the passkey signs over (the WebAuthn challenge). Fixed & documented.
const challenge = sha256('erc4337-v3:passkey:unit-test-vector'); // 32 bytes

// ── Public key (uncompressed SPKI point: 0x04 || x(32) || y(32)) ─────────────────────────────
const pub = p256.getPublicKey(PRIVATE_KEY, false);
const x = pub.slice(1, 33);
const y = pub.slice(33, 65);

// ── clientDataJSON (challenge is base64url, NO padding — matches OZ Base64.encodeURL) ─────────
const challengeB64Url = Buffer.from(challenge).toString('base64url');
const clientDataJSON =
  `{"type":"webauthn.get","challenge":"${challengeB64Url}","origin":"${ORIGIN}","crossOrigin":false}`;

// ── authenticatorData = rpIdHash(32) || flags(1) || signCount(4) ─────────────────────────────
// flags = 0x05 => UP (0x01) + UV (0x04) set; BE/BS unset (consistent: BS=0). Length 37 (> 36 min).
const authenticatorData = Buffer.concat([sha256(RP_ID), Buffer.from([0x05]), Buffer.from([0, 0, 0, 0])]);

// ── message and signature (low-s enforced, as required by OZ P256._isProperSignature) ─────────
const message = sha256(Buffer.concat([authenticatorData, sha256(Buffer.from(clientDataJSON, 'utf8'))]));
const sig = p256.sign(message, PRIVATE_KEY, { lowS: true });
let r, s;
if (typeof sig.toCompactRawBytes === 'function') {
  const raw = sig.toCompactRawBytes();
  r = hex(raw.slice(0, 32));
  s = hex(raw.slice(32, 64));
} else {
  r = to32(sig.r);
  s = to32(sig.s);
}

// ── indices into clientDataJSON expected by OZ WebAuthn ──────────────────────────────────────
const typeIndex = clientDataJSON.indexOf('"type":"');
const challengeIndex = clientDataJSON.indexOf('"challenge":"');

// ── output ────────────────────────────────────────────────────────────────────────────────────
console.log(`
──────────── Solidity (contracts/test/PasskeyAccount.t.sol) ────────────
    bytes32 internal constant PUBKEY_X = ${hex(x)};
    bytes32 internal constant PUBKEY_Y = ${hex(y)};
    bytes32 internal constant USER_OP_HASH = ${hex(challenge)};
    bytes32 internal constant SIG_R = ${r};
    bytes32 internal constant SIG_S = ${s};
    uint256 internal constant CHALLENGE_INDEX = ${challengeIndex};
    uint256 internal constant TYPE_INDEX = ${typeIndex};
    bytes internal constant AUTHENTICATOR_DATA = hex"${Buffer.from(authenticatorData).toString('hex')}";
    string internal constant CLIENT_DATA_JSON =
        '${clientDataJSON}';

──────────── TypeScript (frontend/src/lib/webauthn.test.ts) ────────────
export const VECTOR = {
  privateKey: '0x${PRIVATE_KEY}',
  pubKeyX: '${hex(x)}',
  pubKeyY: '${hex(y)}',
  userOpHash: '${hex(challenge)}',
  r: '${r}',
  s: '${s}',
  challengeIndex: ${challengeIndex},
  typeIndex: ${typeIndex},
  authenticatorData: '${hex(authenticatorData)}',
  clientDataJSON: ${JSON.stringify(clientDataJSON)},
  // uncompressed SPKI point the browser's getPublicKey() trailing 65 bytes must match:
  uncompressedPoint: '${hex(pub)}',
} as const;
────────────────────────────────────────────────────────────────────────
`);
