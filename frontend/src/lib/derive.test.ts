import { describe, it, expect } from 'vitest';
import { isHex } from 'viem';
import { derivePrivateKey, deriveAddress, normalizeAnswer } from './derive';
import { DEMO_ANSWERS } from './demo';

const ANSWERS = DEMO_ANSWERS as string[];

describe('derive (secret-question KDF)', () => {
  it('is deterministic: same answers => same address', () => {
    expect(deriveAddress(ANSWERS)).toBe(deriveAddress(ANSWERS));
  });

  it('normalizes trim + case: formatting differences derive the same key', () => {
    expect(deriveAddress([' Rex ', 'PARIS', 'Inception'])).toBe(
      deriveAddress(['rex', 'paris', 'inception']),
    );
  });

  it('different answers => different address', () => {
    expect(deriveAddress(['rex', 'paris', 'inception'])).not.toBe(
      deriveAddress(['rex', 'paris', 'matrix']),
    );
  });

  it('produces a valid 32-byte private key and a 20-byte address', () => {
    const pk = derivePrivateKey(ANSWERS);
    expect(isHex(pk)).toBe(true);
    expect(pk).toHaveLength(66); // 0x + 64 hex chars = 32 bytes
    expect(deriveAddress(ANSWERS)).toMatch(/^0x[0-9a-fA-F]{40}$/);
  });

  it('normalizeAnswer trims and lowercases', () => {
    expect(normalizeAnswer('  Hello WORLD ')).toBe('hello world');
  });

  // --- DEMO VECTOR (locked) ------------------------------------------------------------------
  // Concrete key/address derived from the PUBLIC demo answers ("rex","paris","inception").
  // Locked as a regression vector: any change to the derivation that would move the address (and
  // orphan the deployed demo account) fails here. These exact values are ALSO cross-checked
  // on-chain in contracts/test/SecretQuestionAccount.t.sol and used as SIGNER_ADDRESS at deploy.
  const DEMO_PRIVATE_KEY = '0x34dbb35f6459589466de132a3b780186ad002c3464057af4c2f00427e91968dd';
  const DEMO_ADDRESS = '0x6791C67E22f99Cf7D019f6e5D4009E9BDB853ACa';

  it('matches the locked demo vector (key + address)', () => {
    expect(derivePrivateKey(ANSWERS)).toBe(DEMO_PRIVATE_KEY);
    expect(deriveAddress(ANSWERS)).toBe(DEMO_ADDRESS);
  });
});
