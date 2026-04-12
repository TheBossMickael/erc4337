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

- **EntryPoint** : contrat singleton déployé par l'Ethereum Foundation.
  - Adresse Sepolia : `0x4337084d9e255ff0702461cf8895ce9e3b5ff108` (v0.8, vérifié actif)
  - Etherscan : https://sepolia.etherscan.io/address/0x4337084d9e255ff0702461cf8895ce9e3b5ff108

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

---

## Interfaces — ce que nos contrats doivent implémenter

### `PackedUserOperation` — la struct centrale (v0.8+)

```solidity
struct PackedUserOperation {
    address sender;              // adresse du SmartAccount
    uint256 nonce;               // anti-replay : 192-bit key | 64-bit sequence
    bytes initCode;              // factory(20 bytes) + factoryData — vide si déjà déployé
    bytes callData;              // ce que le SmartAccount doit exécuter
    bytes32 accountGasLimits;    // uint128(verificationGasLimit) | uint128(callGasLimit)
    uint256 preVerificationGas;  // gas off-chain : compensation bundler
    bytes32 gasFees;             // uint128(maxPriorityFeePerGas) | uint128(maxFeePerGas)
    bytes paymasterAndData;      // paymaster(20) | verifGasLimit(16) | postOpGasLimit(16) | data
    bytes signature;             // validée par validateUserOp() — format libre
}
```

### `IAccount` — interface que SmartAccount.sol doit implémenter

```solidity
interface IAccount {
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData);
}
```

### `IPaymaster` — interface que Paymaster.sol doit implémenter

```solidity
interface IPaymaster {
    function validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external returns (bytes memory context, uint256 validationData);

    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas  // nouveau en v0.8+
    ) external;

    enum PostOpMode {
        opSucceeded,  // exécution réussie
        opReverted    // exécution revert — paymaster paie quand même le gas
    }
}
```

### `validationData` — le return value piégeux

`validateUserOp` et `validatePaymasterUserOp` retournent tous les deux un `uint256` packed :

```
bits   0-159 : adresse aggregator (0x0 = signature valide, 0x1 = SIG_VALIDATION_FAILED)
bits 160-207 : validUntil  — timestamp 6 bytes (0 = infini)
bits 208-255 : validAfter  — timestamp 6 bytes
```

Pour V1 : retourner `0` (succès) ou `1` (échec signature). Ne jamais revert sur une mauvaise
signature — revert uniquement pour les erreurs fatales (nonce invalide, fonds insuffisants).

---

## Flux complet V1

```
1. Script de test crée une PackedUserOperation et la signe avec une clé privée de test
2. UserOp envoyée au Bundler (HTTP JSON-RPC local) via eth_sendUserOperation
3. Bundler valide basiquement la UserOp
4. Bundler envoie une tx handleOps([userOp], beneficiary) à l'EntryPoint Sepolia
5. EntryPoint — verification loop :
   a. Appelle validateUserOp() sur le SmartAccount
   b. Appelle validatePaymasterUserOp() sur le Paymaster
   c. Vérifie que le dépôt du Paymaster sur l'EntryPoint couvre le coût max
6. EntryPoint — execution loop :
   a. Exécute le callData sur le SmartAccount
   b. Appelle postOp() sur le Paymaster si context non vide
   c. Rembourse le surplus de gas, paie le beneficiary
```

---

## Conventions de code

### Solidity

- Version : `pragma solidity ^0.8.24`
- Style OpenZeppelin : NatSpec, checks-effects-interactions
- Nommage : `_param` pour les paramètres de fonction, `s_variable` pour le storage, `CONSTANTE` pour les constantes
- Toujours émettre des events sur les changements d'état importants
- Jamais de `tx.origin`
- Toujours vérifier `msg.sender == address(entryPoint)` dans `validateUserOp` et `validatePaymasterUserOp`

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
ENTRYPOINT_ADDRESS=0x4337084d9e255ff0702461cf8895ce9e3b5ff108
SMART_ACCOUNT_ADDRESS=
PAYMASTER_ADDRESS=
```

---

## Ressources clés

- Spec ERC-4337 : https://eips.ethereum.org/EIPS/eip-4337
- Repo de référence (lire, pas copier) : https://github.com/eth-infinitism/account-abstraction
- EntryPoint Sepolia Etherscan : https://sepolia.etherscan.io/address/0x4337084d9e255ff0702461cf8895ce9e3b5ff108
- Viem docs : https://viem.sh

---

## Pédagogie

- Toujours expliquer le "pourquoi" avant le "comment"
- Exemples numériques concrets sur les concepts économiques et cryptographiques
- Signaler les risques de sécurité, edge cases, et mauvaises pratiques
- Ne pas valider une approche par défaut — challenger si nécessaire
- Définir un concept avant de l'utiliser