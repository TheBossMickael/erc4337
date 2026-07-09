// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseAccount} from "./BaseAccount.sol";
import {PackedUserOperation} from "./interfaces/IAccount.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title SmartAccount
/// @notice ERC-4337 smart wallet (V1) — single-owner ECDSA validation.
/// @dev Auth by POSSESSION: the owner holds a fixed private key and signs UserOps with it.
///      Only `_validateSignature` (+ the admin hook) is scheme-specific; everything else lives
///      in BaseAccount.
contract SmartAccount is BaseAccount {
    /// @dev Account owner: the only address allowed to sign valid UserOps.
    address private s_owner;

    event SmartAccountInitialized(address indexed entryPoint, address indexed owner);

    /// @param _entryPoint EntryPoint address (0x4337...108 on Sepolia)
    /// @param _owner      Owner's EOA address — signs UserOps off-chain
    constructor(address _entryPoint, address _owner) BaseAccount(_entryPoint) {
        s_owner = _owner;
        emit SmartAccountInitialized(_entryPoint, _owner);
    }

    /// @inheritdoc BaseAccount
    /// @dev Convention: the client signs with personal_sign (EIP-191), so we rebuild
    ///      toEthSignedMessageHash(userOpHash) before recovery. ECDSA.tryRecover guards against
    ///      malleability and never reverts on a malformed signature.
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        override
        returns (uint256)
    {
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(ethSignedHash, userOp.signature);
        if (err != ECDSA.RecoverError.NoError || recovered != s_owner) {
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }

    /// @inheritdoc BaseAccount
    function _authorizedAdmin() internal view override returns (address) {
        return s_owner;
    }

    /// @notice Owner address.
    function owner() external view returns (address) {
        return s_owner;
    }
}
