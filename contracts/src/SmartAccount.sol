// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccount, PackedUserOperation} from "./interfaces/IAccount.sol";

/// @title SmartAccount
/// @notice Smart wallet ERC-4337 — remplace un EOA classique.
///         Chaque utilisateur déploie sa propre instance de ce contrat.
/// @dev V1 : validation ECDSA standard, 1 owner, gas sponsorisé par un Paymaster externe.
///      Implémente IAccount directement, sans hériter de BaseAccount.
contract SmartAccount is IAccount {

    /// @dev Adresse de l'EntryPoint ERC-4337 v0.8 sur Sepolia.
    ///      Immutable : fixée au déploiement, stockée dans le bytecode (pas de SLOAD).
    address private immutable i_entryPoint;

    /// @dev Propriétaire du compte : seule adresse autorisée à signer des UserOps valides.
    address private s_owner;

    /// @notice Initialise le SmartAccount avec son EntryPoint et son owner.
    /// @param _entryPoint Adresse de l'EntryPoint (0x4337084d9e255ff0702461cf8895ce9e3b5ff108 sur Sepolia)
    /// @param _owner      Adresse EOA du propriétaire — signe les UserOps off-chain
    constructor(address _entryPoint, address _owner) {
        i_entryPoint = _entryPoint;
        s_owner = _owner;
    }

    /// @notice Permet au contrat de recevoir de l'ETH.
    ///         Nécessaire pour le prefund (envoyer des ETH à l'EntryPoint)
    ///         et pour recevoir les remboursements de gas excédentaire.
    receive() external payable {}

    /// @notice Transfère le prefund à l'EntryPoint si le dépôt du compte est insuffisant.
    /// @dev Appelé en début de validateUserOp, avant la vérification de signature.
    ///      missingAccountFunds = maxCost - dépôt actuel du compte sur l'EntryPoint.
    ///      Si un Paymaster est présent, ce paramètre vaut 0 et la fonction ne fait rien.
    ///      On ignore le return value du call : l'EntryPoint vérifie lui-même la réception.
    /// @param missingAccountFunds ETH manquant à envoyer à l'EntryPoint (en wei)
    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(i_entryPoint).call{value: missingAccountFunds}("");
            (success);
        }
    }

    /// @notice Valide une UserOperation avant son exécution par l'EntryPoint.
    /// @dev Appelé exclusivement par l'EntryPoint pendant la verification loop.
    ///      RÈGLE ABSOLUE : ne jamais revert sur une mauvaise signature — retourner 1.
    ///      Revert uniquement sur erreur fatale (ex : impossible de payer le prefund).
    /// @param userOp             La UserOperation à valider
    /// @param userOpHash         Hash de la UserOp calculé par l'EntryPoint (EIP-712-like)
    /// @param missingAccountFunds ETH manquant sur le dépôt de l'EntryPoint (0 si Paymaster présent)
    /// @return 0 = signature valide, 1 = signature invalide
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds) external returns (uint256) {
        // Seul l'EntryPoint est autorisé à appeler cette fonction
        require(msg.sender == i_entryPoint, "Seul EntryPoint peut appeler");

        // Payer le prefund avant la validation — l'EntryPoint en a besoin peu importe le résultat
        _payPrefund(missingAccountFunds);

        // Reconstruire le hash effectivement signé par le wallet off-chain.
        // eth_sign ajoute automatiquement ce préfixe EIP-191 avant de signer —
        // on doit le reproduire on-chain pour retrouver la bonne adresse via ecrecover.
        bytes32 hashFinal = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));

        // Décomposer la signature (65 bytes) en ses 3 composantes ECDSA.
        // Layout mémoire d'un `bytes` : [32 bytes de longueur][données].
        // r = bytes  0-31, s = bytes 32-63, v = byte 64
        bytes memory sig = userOp.signature;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))          // saute la longueur, lit r
            s := mload(add(sig, 64))          // saute longueur + r, lit s
            v := byte(0, mload(add(sig, 96))) // saute longueur + r + s, lit v
        }

        // ecrecover retourne l'adresse qui a produit cette signature.
        // Retourne address(0) si la signature est malformée.
        address recovered = ecrecover(hashFinal, v, r, s);

        // Comparaison : 0 = succès, 1 = échec — jamais revert
        return recovered == s_owner ? 0 : 1;
    }
}
