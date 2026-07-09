import { useState, type FormEvent } from 'react';
import type { Hex } from 'viem';
import { config } from '../config';
import { DEMO_QUESTIONS } from '../lib/demo';
import { deriveAddress } from '../lib/derive';
import { deployAccount } from '../lib/bundler';

interface Props {
  onAccountCreated: (account: Hex) => void;
}

type Status =
  | { kind: 'idle' }
  | { kind: 'deploying'; signer: Hex }
  | { kind: 'done'; account: Hex; signer: Hex }
  | { kind: 'error'; message: string };

export function SetupScreen({ onAccountCreated }: Props) {
  const [answers, setAnswers] = useState<string[]>(DEMO_QUESTIONS.map(() => ''));
  const [status, setStatus] = useState<Status>({ kind: 'idle' });

  const setAnswer = (i: number, value: string) =>
    setAnswers((prev) => prev.map((a, idx) => (idx === i ? value : a)));

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    // The key NEVER leaves the browser — we only derive and send the resulting ADDRESS.
    const signer = deriveAddress(answers, config.salt);
    setStatus({ kind: 'deploying', signer });
    try {
      const account = await deployAccount(signer);
      setStatus({ kind: 'done', account, signer });
    } catch (err) {
      setStatus({ kind: 'error', message: err instanceof Error ? err.message : String(err) });
    }
  }

  const deploying = status.kind === 'deploying';
  const allFilled = answers.every((a) => a.trim().length > 0);

  return (
    <section className="card">
      <h2>Create your account</h2>
      <p className="muted small">
        Pick <strong>your own secret answers</strong>. Your browser derives an address and asks the
        backend to deploy a <code>SecretQuestionAccount</code> for it — your answers never leave
        this page (the deployer key stays server-side, <em>deployer ≠ signer</em>).
      </p>

      <form onSubmit={onSubmit}>
        {DEMO_QUESTIONS.map((question, i) => (
          <label key={question} className="field">
            <span>{question}</span>
            <input
              type="text"
              value={answers[i] ?? ''}
              onChange={(e) => setAnswer(i, e.target.value)}
              autoComplete="off"
              spellCheck={false}
              disabled={deploying}
            />
          </label>
        ))}

        <button type="submit" disabled={deploying || !allFilled}>
          {deploying ? (
            <>
              <span className="spinner" />
              Deploying…
            </>
          ) : (
            'Create my account'
          )}
        </button>
      </form>

      {status.kind === 'error' && <p className="error">❌ {status.message}</p>}

      {status.kind === 'done' && (
        <div className="result">
          <p>
            ✅ Account deployed: <code>{status.account}</code>
          </p>
          <p className="muted">
            Signer (derived from your answers): <code>{status.signer}</code>
          </p>
          <button type="button" onClick={() => onAccountCreated(status.account)}>
            Use this account now →
          </button>
        </div>
      )}
    </section>
  );
}
