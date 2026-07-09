// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseAccount} from "./BaseAccount.sol";
import {PackedUserOperation} from "./interfaces/IAccount.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title SecretQuestionAccount
/// @notice ERC-4337 smart wallet (V2) — auth by KNOWLEDGE (secret questions).
/// @dev The validation logic is IDENTICAL to V1 (ECDSA recover == stored address). What changes
///      is the AUTH MODEL, not the curve: the signing key is never stored nor held as a standing
///      EOA — it is re-derived client-side from the answers to secret questions
///      (KDF(salt || answers) -> private key -> address). Only the resulting ADDRESS is stored
///      here (`s_signerAddress`). Proving knowledge of the answers == producing a valid signature.
///
///      SECURITY MODEL (brain wallet): the answer IS the private key. Public/weak answers => the
///      account is drainable by anyone. This is an intentionally insecure, honest teaching demo,
///      NOT a production wallet. See the README "Security model" section.
contract SecretQuestionAccount is BaseAccount {
    /// @dev Address derived off-chain from the answers — the only address allowed to sign UserOps.
    ///      We never see the answers nor the private key on-chain, only this address.
    address private s_signerAddress;

    event SecretQuestionAccountInitialized(address indexed entryPoint, address indexed signerAddress);

    /// @param _entryPoint    EntryPoint address (0x4337...108 on Sepolia)
    /// @param _signerAddress Address derived from the secret answers (deployer != signer)
    constructor(address _entryPoint, address _signerAddress) BaseAccount(_entryPoint) {
        s_signerAddress = _signerAddress;
        emit SecretQuestionAccountInitialized(_entryPoint, _signerAddress);
    }

    /// @inheritdoc BaseAccount
    /// @dev Same scheme as V1: personal_sign convention => rebuild toEthSignedMessageHash before
    ///      recovery, compare against the address derived from the answers.
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        override
        returns (uint256)
    {
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(ethSignedHash, userOp.signature);
        if (err != ECDSA.RecoverError.NoError || recovered != s_signerAddress) {
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }

    /// @inheritdoc BaseAccount
    function _authorizedAdmin() internal view override returns (address) {
        return s_signerAddress;
    }

    /// @notice Address derived from the secret answers.
    function signerAddress() external view returns (address) {
        return s_signerAddress;
    }
}
