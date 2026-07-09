import { useState, useEffect, type FormEvent } from 'react';
import type { Hex } from 'viem';
import { config } from '../config';
import { DEMO_QUESTIONS, DEMO_ANSWERS } from '../lib/demo';
import { runIncrement, type IncrementOutcome } from '../lib/userOpFlow';
import { getCount } from '../lib/chain';
import { friendlyError } from '../lib/errors';

interface Props {
  account: Hex;
  isDemoAccount: boolean;
}

type Status =
  | { kind: 'idle' }
  | { kind: 'running' }
  | { kind: 'done'; outcome: IncrementOutcome }
  | { kind: 'error'; message: string };

export function UseScreen({ account, isDemoAccount }: Props) {
  // Empty inputs on purpose: the user types the answers (proves it is a real input, not a trick).
  const [answers, setAnswers] = useState<string[]>(DEMO_QUESTIONS.map(() => ''));
  const [status, setStatus] = useState<Status>({ kind: 'idle' });
  const [currentCount, setCurrentCount] = useState<bigint | null>(null);

  // Read the shared Counter value once on load, so the before -> after has context.
  useEffect(() => {
    let cancelled = false;
    getCount()
      .then((c) => {
        if (!cancelled) setCurrentCount(c);
      })
      .catch(() => {
        /* transient RPC issue: just don't show the live count */
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const setAnswer = (i: number, value: string) =>
    setAnswers((prev) => prev.map((a, idx) => (idx === i ? value : a)));

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setStatus({ kind: 'running' });
    try {
      const outcome = await runIncrement(account, answers);
      setCurrentCount(outcome.countAfter);
      setStatus({ kind: 'done', outcome });
    } catch (err) {
      const raw = err instanceof Error ? err.message : String(err);
      setStatus({ kind: 'error', message: friendlyError(raw) });
    }
  }

  const running = status.kind === 'running';
  const allFilled = answers.every((a) => a.trim().length > 0);

  return (
    <section className="card">
      <p className="account-line">
        Account <code>{account}</code>{' '}
        {isDemoAccount ? (
          <span className="badge">shared demo</span>
        ) : (
          <span className="badge badge-own">yours</span>
        )}
      </p>

      {currentCount !== null && (
        <p className="muted small">
          Counter is currently at <strong>{currentCount.toString()}</strong>.
        </p>
      )}

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
              disabled={running}
            />
          </label>
        ))}

        {isDemoAccount && (
          <p className="info">
            Demo answers are <strong>public</strong> (insecure on purpose):{' '}
            <code>{DEMO_ANSWERS.join('  ·  ')}</code>. Anyone can drive this shared account.
          </p>
        )}

        <button type="submit" disabled={running || !allFilled}>
          {running ? (
            <>
              <span className="spinner" />
              Sending…
            </>
          ) : (
            'Run (gasless)'
          )}
        </button>

        {running && (
          <p className="muted small" style={{ marginTop: '0.75rem' }}>
            Waiting for the Sepolia block (~15s)…
          </p>
        )}
      </form>

      {status.kind === 'error' && <p className="error">❌ {status.message}</p>}

      {status.kind === 'done' && (
        <div className="result">
          <div className="counter">
            <span className="counter-before">{status.outcome.countBefore.toString()}</span>
            <span className="counter-arrow">→</span>
            <span className="counter-after">{status.outcome.countAfter.toString()}</span>
          </div>
          <p className="muted small" style={{ textAlign: 'center' }}>
            One Ethereum transaction (the bundler’s <code>handleOps</code>); your increment ran as an
            internal call inside it — no wallet, no gas on your side.
          </p>
          <p style={{ textAlign: 'center' }}>
            <a
              href={`${config.explorerUrl}/tx/${status.outcome.txHash}`}
              target="_blank"
              rel="noreferrer"
            >
              View the bundler transaction ↗
            </a>
          </p>
          <details className="tech">
            <summary>Technical details</summary>
            <p className="muted small">
              Derived signer: <code>{status.outcome.signer}</code>
            </p>
            <p className="muted small">
              userOpHash: <code>{status.outcome.userOpHash}</code>
            </p>
            <p className="muted small">
              tx: <code>{status.outcome.txHash}</code>
            </p>
          </details>
        </div>
      )}
    </section>
  );
}
