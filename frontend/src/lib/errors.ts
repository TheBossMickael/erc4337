/**
 * Maps a raw bundler/chain/WebAuthn error message to a friendly, user-facing sentence.
 * The bundler rejects invalid UserOps at simulation and returns the decoded EntryPoint reason
 * (e.g. "UserOperation rejected: AA24 signature error"), so we can branch on the AA code.
 */
export function friendlyError(raw: string): string {
  if (/AA24/i.test(raw)) {
    return 'Passkey signature rejected — this passkey does not control the account.';
  }
  if (/AA31/i.test(raw)) {
    return 'The Paymaster is out of funds — top up its deposit and retry.';
  }
  if (/NotAllowed|cancel|timed? ?out|permission/i.test(raw)) {
    return 'Passkey prompt cancelled, timed out, or blocked by this browser. On iPhone/iPad, open this page in Safari — other iOS browsers can\'t use passkeys.';
  }
  if (/Failed to fetch|NetworkError|ECONNREFUSED/i.test(raw)) {
    return 'Cannot reach the bundler — is it running?';
  }
  return raw;
}
