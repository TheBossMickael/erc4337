import { useState } from 'react';
import type { Hex } from 'viem';
import { config, missingEnv } from './config';
import { UseScreen } from './screens/UseScreen';
import { SetupScreen } from './screens/SetupScreen';

const STORAGE_KEY = 'erc4337.v2.account';

export function App() {
  if (missingEnv.length > 0) {
    return <ConfigError missing={missingEnv} />;
  }
  return <AppMain />;
}

type Screen = 'use' | 'setup';

function AppMain() {
  const [screen, setScreen] = useState<Screen>('use');
  const [account, setAccount] = useState<Hex>(
    (localStorage.getItem(STORAGE_KEY) as Hex | null) ?? config.demoAccount,
  );

  const isDemoAccount = account.toLowerCase() === config.demoAccount.toLowerCase();

  // SETUP -> USE handoff: keep the new account in memory + localStorage. No .env edit, no restart.
  function onAccountCreated(newAccount: Hex) {
    setAccount(newAccount);
    localStorage.setItem(STORAGE_KEY, newAccount);
    setScreen('use');
  }

  function resetToDemo() {
    setAccount(config.demoAccount);
    localStorage.removeItem(STORAGE_KEY);
  }

  return (
    <main className="app">
      <header>
        <h1>🔑 Secret-Question Wallet</h1>
        <p className="tagline">
          Answer your questions. It signs for you — no wallet, no seed phrase, no gas.
        </p>

        <nav>
          <button className={screen === 'use' ? 'tab active' : 'tab'} onClick={() => setScreen('use')}>
            Use
          </button>
          <button className={screen === 'setup' ? 'tab active' : 'tab'} onClick={() => setScreen('setup')}>
            Create account
          </button>
          {!isDemoAccount && (
            <button className="tab ghost" onClick={resetToDemo}>
              ↺ demo account
            </button>
          )}
        </nav>

        <details className="how">
          <summary>How it works</summary>
          <ol>
            <li>You answer your secret questions in your browser.</li>
            <li>
              Your browser derives a private key from the answers and <strong>signs</strong> a
              request — locally; the answers stay on your machine.
            </li>
            <li>
              A <strong>bundler</strong> submits it for you; a <strong>Paymaster</strong> pays the gas.
            </li>
            <li>
              → A real Sepolia transaction happens with <strong>no wallet extension, no seed phrase,
              no gas</strong>. That’s ERC-4337 account abstraction.
            </li>
          </ol>
          <p className="muted small">
            Your on-chain account (a <code>SecretQuestionAccount</code>) stores only the address
            derived from your answers — never the answers themselves. In this shared demo the answers
            are <strong>public on purpose</strong> (so anyone can try it); a real account would use
            secret answers only you know. Full details &amp; security model are in the project README.
          </p>
        </details>
      </header>

      {screen === 'use' ? (
        // key={account} -> remount (reset inputs/result, refetch counter) when the account changes
        <UseScreen key={account} account={account} isDemoAccount={isDemoAccount} />
      ) : (
        <SetupScreen onAccountCreated={onAccountCreated} />
      )}

      <footer className="small">
        Pedagogical demo on Sepolia — demo answers are public on purpose (brain-wallet model,
        intentionally insecure).
      </footer>
    </main>
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
