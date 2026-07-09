/**
 * Maps a raw bundler/chain error message to a friendly, user-facing sentence.
 * The bundler now rejects invalid UserOps at simulation and returns the decoded EntryPoint reason
 * (e.g. "UserOperation rejected: AA24 signature error"), so we can branch on the AA code.
 */
export function friendlyError(raw: string): string {
  if (/AA24/i.test(raw)) {
    return 'Wrong answers.';
  }
  if (/AA31/i.test(raw)) {
    return 'The Paymaster is out of funds — top up its deposit and retry.';
  }
  if (/Failed to fetch|NetworkError|ECONNREFUSED/i.test(raw)) {
    return 'Cannot reach the bundler — is it running?';
  }
  return raw;
}
