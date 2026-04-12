# ERC-4337 — Account Abstraction from scratch

Implémentation complète d'un système ERC-4337 :
- **Smart Account** : contrat wallet avec logique de validation custom
- **Paymaster** : sponsoring du gas
- **Bundler** : serveur Node.js/TypeScript qui orchestre les UserOperations

## Stack
- Solidity + Foundry (contracts)
- TypeScript + Node.js + Viem (bundler)
- Sepolia testnet

## Structure
erc4337/
├── contracts/   # Foundry — SmartAccount, Paymaster
├── bundler/     # Node.js — Bundler JSON-RPC server
├── frontend/    # (V2)
└── docs/        # Architecture, décisions, notes