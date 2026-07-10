import { useState, useEffect } from 'react';
import type { Hex } from 'viem';
import { config, missingEnv } from './config';
import { getAccountAddress, getCount } from './lib/chain';
import { runPasskeyIncrement, type IncrementOutcome } from './lib/passkeyFlow';
import type { Passkey } from './lib/webauthn';
import { friendlyError } from './lib/errors';

const STORAGE_KEY = 'erc4337.v3.passkey';

function loadPasskey(): Passkey | null {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as Passkey;
  } catch {
    return null;
  }
}

export function App() {
  if (missingEnv.length > 0) {
    return <ConfigError missing={missingEnv} />;
  }
  return <AppMain />;
}

type Status =
  | { kind: 'idle' }
  | { kind: 'running' }
  | { kind: 'done'; outcome: IncrementOutcome }
  | { kind: 'error'; message: string };

function AppMain() {
  const [passkey, setPasskey] = useState<Passkey | null>(() => loadPasskey());
  const [account, setAccount] = useState<Hex | null>(null);
  const [status, setStatus] = useState<Status>({ kind: 'idle' });
  const [currentCount, setCurrentCount] = useState<bigint | null>(null);

  // Read the shared Counter once on load, so the before -> after has context.
  useEffect(() => {
    let cancelled = false;
    getCount()
      .then((c) => !cancelled && setCurrentCount(c))
      .catch(() => {
        /* transient RPC issue: just don't show the live count */
      });
    return () => {
      cancelled = true;
    };
  }, []);

  // Resolve the counterfactual account address whenever we have a passkey (before any tx).
  useEffect(() => {
    if (!passkey) {
      setAccount(null);
      return;
    }
    let cancelled = false;
    getAccountAddress(passkey.x, passkey.y)
      .then((a) => !cancelled && setAccount(a))
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [passkey]);

  const running = status.kind === 'running';

  async function onRun() {
    setStatus({ kind: 'running' });
    try {
      const outcome = await runPasskeyIncrement(passkey);
      setPasskey(outcome.passkey);
      localStorage.setItem(STORAGE_KEY, JSON.stringify(outcome.passkey));
      setCurrentCount(outcome.countAfter);
      setStatus({ kind: 'done', outcome });
    } catch (err) {
      const raw = err instanceof Error ? err.message : String(err);
      setStatus({ kind: 'error', message: friendlyError(raw) });
    }
  }

  function forgetPasskey() {
    localStorage.removeItem(STORAGE_KEY);
    setPasskey(null);
    setAccount(null);
    setStatus({ kind: 'idle' });
  }

  return (
    <main className="app">
      <header>
        <h1>🔑 Passkey Wallet</h1>
        <p className="tagline">
          Tap once. Your device signs with Face ID / Touch ID / Windows Hello — no wallet, no seed
          phrase, no gas.
        </p>

        <details className="how">
          <summary>How it works</summary>
          <ol>
            <li>
              Your browser creates (or reuses) a <strong>passkey</strong> — a P-256 key held by your
              device's authenticator. The private key never leaves the device.
            </li>
            <li>
              You <strong>sign</strong> a request with your biometrics; the account address is derived
              from the passkey's public key.
            </li>
            <li>
              A <strong>bundler</strong> submits it; a <strong>Paymaster</strong> pays the gas. On
              first use, that same transaction also <strong>deploys your account</strong> (a factory
              + <code>initCode</code>) — no separate step.
            </li>
            <li>
              → A real Sepolia transaction happens with <strong>no wallet extension, no seed phrase,
              no gas</strong>. That's ERC-4337 account abstraction with WebAuthn.
            </li>
          </ol>
          <p className="muted small">
            Your on-chain account (a <code>PasskeyAccount</code>) stores only your passkey's public key
            (x, y). One browser = one account: passkeys are bound to this device, so there is no shared
            demo account (unlike V2) and no cross-device sync. Full details in the project README.
          </p>
        </details>
      </header>

      <section className="card">
        <p className="account-line">
          {account ? (
            <>
              Account <code>{account}</code> <span className="badge badge-own">yours</span>
            </>
          ) : (
            <span className="muted">No passkey yet on this browser — your first tap creates one.</span>
          )}
        </p>

        {currentCount !== null && (
          <p className="muted small">
            Counter is currently at <strong>{currentCount.toString()}</strong>.
          </p>
        )}

        {!passkey && (
          <p className="info">
            First tap prompts your biometrics <strong>twice</strong>: once to register the passkey,
            once to sign. After that, a single prompt per run.
          </p>
        )}

        <button type="button" onClick={onRun} disabled={running}>
          {running ? (
            <>
              <span className="spinner" />
              Working…
            </>
          ) : passkey ? (
            'Increment the counter (gasless)'
          ) : (
            'Create a passkey & run (gasless)'
          )}
        </button>

        {running && (
          <p className="muted small" style={{ marginTop: '0.75rem' }}>
            Approve the passkey prompt, then wait for the Sepolia block (~15s)…
          </p>
        )}

        {passkey && (
          <button type="button" className="tab ghost" style={{ marginTop: '0.75rem' }} onClick={forgetPasskey}>
            ↺ forget this passkey
          </button>
        )}

        {status.kind === 'error' && <p className="error">❌ {status.message}</p>}

        {status.kind === 'done' && <Result outcome={status.outcome} />}
      </section>

      <footer className="small">
        Pedagogical demo on Sepolia — passkeys (WebAuthn P-256) + counterfactual factory deployment.
      </footer>
    </main>
  );
}

function Result({ outcome }: { outcome: IncrementOutcome }) {
  return (
    <div className="result">
      <div className="counter">
        <span className="counter-before">{outcome.countBefore.toString()}</span>
        <span className="counter-arrow">→</span>
        <span className="counter-after">{outcome.countAfter.toString()}</span>
      </div>
      <p className="muted small" style={{ textAlign: 'center' }}>
        One Ethereum transaction (the bundler's <code>handleOps</code>)
        {outcome.deployed ? ' — it deployed your account AND ran the increment' : ''}; no wallet, no
        gas on your side.
      </p>
      <p style={{ textAlign: 'center' }}>
        <a href={`${config.explorerUrl}/tx/${outcome.txHash}`} target="_blank" rel="noreferrer">
          View the bundler transaction ↗
        </a>
      </p>
      <details className="tech">
        <summary>Technical details</summary>
        <p className="muted small">
          Account: <code>{outcome.account}</code>
          {outcome.deployed ? ' (deployed by this op)' : ''}
        </p>
        <p className="muted small">
          Passkey public key: <code>{outcome.passkey.x}</code> / <code>{outcome.passkey.y}</code>
        </p>
        <p className="muted small">
          userOpHash: <code>{outcome.userOpHash}</code>
        </p>
        <p className="muted small">
          tx: <code>{outcome.txHash}</code>
        </p>
      </details>
    </div>
  );
}

function ConfigError({ missing }: { missing: string[] }) {
  return (
    <main className="app">
      <section className="card">
        <h2>⚙️ Missing configuration</h2>
        <p>
          Copy <code>frontend/.env.example</code> to <code>frontend/.env</code> and fill these in:
        </p>
        <ul>
          {missing.map((key) => (
            <li key={key}>
              <code>{key}</code>
            </li>
          ))}
        </ul>
        <p className="muted small">Then restart the dev server (npm run dev).</p>
      </section>
    </main>
  );
}
