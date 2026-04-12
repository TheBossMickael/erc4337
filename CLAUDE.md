# CLAUDE.md — ERC-4337 Account Abstraction from scratch

## Contexte développeur

Étudiant ingénieur (Télécom Saint-Étienne), stage Banque de France sur interopérabilité ZK-Rollups.
Background : JS, C++, Python. Solidity/Foundry en apprentissage. Node.js familier mais pas expert.
Objectif long terme : ingénieur blockchain/web3.

---

## Ce qu'on construit

Implémentation complète d'un système ERC-4337 from scratch, à des fins pédagogiques.
Déployé sur Sepolia testnet — zéro argent réel.

### Les 3 composants

- **SmartAccount** (Solidity) : contrat wallet avec logique de validation custom. Implémente `validateUserOp()`. Remplace un EOA classique.
- **Paymaster** (Solidity) : contrat qui paie le gas à la place de l'utilisateur.
- **Bundler** (Node.js/TypeScript) : serveur JSON-RPC qui collecte des UserOperations, les bundle, les envoie à l'EntryPoint sur Sepolia.

### Ce qu'on N'implémente PAS

- **EntryPoint** : contrat singleton déployé par l'Ethereum Foundation, adresse Sepolia fixe : `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789`

---

## Stack technique

- **Solidity + Foundry** : smart contracts, tests, déploiement
- **TypeScript + Node.js + Viem** : bundler
- **Sepolia** : testnet de déploiement
- **OpenZeppelin** : standards ERC

---

## Structure du monorepo

```
erc4337/
├── contracts/
│   ├── src/            <- SmartAccount.sol, Paymaster.sol
│   ├── test/           <- tests Foundry
│   ├── script/         <- scripts de déploiement
│   └── foundry.toml
├── bundler/
│   ├── src/
│   │   └── index.ts    <- point d'entrée du serveur
│   ├── package.json
│   └── tsconfig.json
├── frontend/           <- V2, vide pour l'instant
├── docs/               <- architecture, décisions
├── CLAUDE.md
└── README.md
```

---

## Décisions d'architecture

### Scope V1

- 1 seul SmartAccount avec validation ECDSA standard (pas encore WebAuthn)
- 1 Paymaster simple : sponsoring inconditionnel du gas
- 1 Bundler minimaliste : 1 UserOp par bundle, pas de simulation avancée
- Déployé sur Sepolia, testé end-to-end

### Hors scope V1 (évolutions futures)

- Session keys
- WebAuthn / Passkeys (P-256)
- Social recovery
- Bundling multi-UserOp
- Frontend

### UserOperation — la struct centrale

```solidity
struct UserOperation {
    address sender;                // adresse du SmartAccount
    uint256 nonce;                 // anti-replay
    bytes initCode;                // pour déployer le SmartAccount si pas encore déployé
    bytes callData;                // ce que le SmartAccount doit exécuter
    uint256 callGasLimit;
    uint256 verificationGasLimit;
    uint256 preVerificationGas;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    bytes paymasterAndData;        // adresse du Paymaster + données
    bytes signature;               // signature validée par validateUserOp()
}
```

### Flux complet V1

```
1. Script de test crée un UserOp et le signe avec une clé privée de test
2. UserOp envoyé au Bundler (HTTP JSON-RPC local)
3. Bundler valide basiquement le UserOp
4. Bundler envoie une tx à l'EntryPoint Sepolia
5. EntryPoint appelle validateUserOp() sur le SmartAccount
6. EntryPoint appelle validatePaymasterUserOp() sur le Paymaster
7. Si tout ok -> EntryPoint exécute le callData
```

---

## Conventions de code

### Solidity

- Version : `pragma solidity ^0.8.24`
- Style OpenZeppelin : NatSpec, checks-effects-interactions
- Nommage : `_param` pour les paramètres de fonction, `s_variable` pour le storage, `CONSTANTE` pour les constantes
- Toujours émettre des events sur les changements d'état importants
- Jamais de `tx.origin`

### TypeScript

- Strict mode activé
- Async/await uniquement, pas de `.then()`
- Types explicites, pas de `any`
- Un fichier par responsabilité

### Git

- Commits : `type: description` (feat, fix, chore, docs, test)
- Une feature = une branche = une PR

---

## Commandes utiles

### Contracts

```bash
cd contracts
forge build
forge test
forge test -vvv
forge script script/Deploy.s.sol
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast
```

### Bundler

```bash
cd bundler
npm run dev
npm run build
npm run start
```

---

## Variables d'environnement (bundler/.env)

```
SEPOLIA_RPC_URL=
PRIVATE_KEY=
ENTRYPOINT_ADDRESS=0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789
SMART_ACCOUNT_ADDRESS=
PAYMASTER_ADDRESS=
```

---

## Ressources clés

- Spec ERC-4337 : https://eips.ethereum.org/EIPS/eip-4337
- Repo de référence (lire, pas copier) : https://github.com/eth-infinitism/account-abstraction
- EntryPoint Sepolia Etherscan : https://sepolia.etherscan.io/address/0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789
- Viem docs : https://viem.sh

---

## Pédagogie

- Toujours expliquer le "pourquoi" avant le "comment"
- Exemples numériques concrets sur les concepts économiques et cryptographiques
- Signaler les risques de sécurité, edge cases, et mauvaises pratiques
- Ne pas valider une approche par défaut — challenger si nécessaire
- Définir un concept avant de l'utiliser