import { keccak256, concat, stringToHex, type Hex } from 'viem';
import { privateKeyToAccount, type PrivateKeyAccount } from 'viem/accounts';

/**
 * V2 — Authentication by KNOWLEDGE (secret questions).
 *
 * Derivation chain:  answers -> KDF(salt || answers) -> private key -> address.
 * Only the resulting ADDRESS is stored on-chain (SecretQuestionAccount.s_signerAddress).
 * Proving knowledge of the answers == producing a valid signature for that address. The contract
 * never recomputes this KDF: it only stores the address, so there is no on-chain encoding to match.
 *
 * SECURITY MODEL (brain wallet): the answers ARE the private key. Public/weak answers => the
 * account is drainable by anyone. This demo uses PUBLIC answers on purpose and is intentionally
 * insecure (see README "Security model"). Hardening (NOT implemented here): secret high-entropy
 * answers + a SLOW KDF (scrypt/Argon2) instead of keccak256, to resist brute force.
 *
 * INVARIANT: the pre-image encoding must stay deterministic — same answers (after normalization) +
 * same salt => same key, on every machine, every time. Changing it would orphan existing accounts.
 */

/**
 * Public, documented salt (domain separation). Public on purpose for this demo; even in a real
 * deployment the salt would stay public — secrecy must come from the answers, not the salt.
 */
export const DEFAULT_SALT: Hex = keccak256(stringToHex('erc4337-v2:secret-question:public-demo-salt'));

/**
 * Separator joining the normalized answers before hashing. A newline keeps the pre-image readable
 * and cannot be typed in the single-line answer inputs. The demo uses a FIXED set of 3 required
 * answers, so separator ambiguity across answer counts is a non-issue.
 */
const ANSWER_SEPARATOR = '\n';

/**
 * Normalizes one answer so trivial formatting differences don't change the derived key.
 * Trim + lowercase: "  Paris " and "paris" derive the SAME key.
 */
export function normalizeAnswer(answer: string): string {
  return answer.trim().toLowerCase();
}

/**
 * Derives the private key from the answers. Deterministic.
 * Pre-image = salt (32 bytes) || utf8(normalized answers joined by the separator).
 */
export function derivePrivateKey(answers: string[], salt: Hex = DEFAULT_SALT): Hex {
  const normalized = answers.map(normalizeAnswer).join(ANSWER_SEPARATOR);
  return keccak256(concat([salt, stringToHex(normalized)]));
}

/** Derives the viem signer account from the answers (used to sign the userOpHash). */
export function deriveAccount(answers: string[], salt: Hex = DEFAULT_SALT): PrivateKeyAccount {
  return privateKeyToAccount(derivePrivateKey(answers, salt));
}

/** Derives just the address — the value stored on-chain as the account's signer. */
export function deriveAddress(answers: string[], salt: Hex = DEFAULT_SALT): Hex {
  return deriveAccount(answers, salt).address;
}
