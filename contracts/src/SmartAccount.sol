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
}
