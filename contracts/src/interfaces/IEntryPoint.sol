// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PackedUserOperation} from "./IAccount.sol";

/// @title IEntryPoint — MINIMAL interface of the ERC-4337 v0.8 EntryPoint
/// @notice We only redeclare the functions our contracts and scripts actually call.
///         The real EntryPoint (singleton deployed by the Ethereum Foundation) exposes
///         many more, but there is no need to copy them all: an interface only needs the
///         signatures we actually invoke.
/// @dev    Sepolia v0.8 address: 0x4337084d9e255ff0702461cf8895ce9e3b5ff108
interface IEntryPoint {
    /// @notice Credits an account's "deposit" on the EntryPoint (internal accounting).
    /// @dev    This is HOW a Paymaster is funded: we don't send ETH to the Paymaster
    ///         itself, we deposit on its behalf here. The EntryPoint draws from this
    ///         balance to reimburse the bundler.
    /// @param account Address whose deposit is being funded (e.g. address(paymaster))
    function depositTo(address account) external payable;

    /// @notice Reads an account's deposited balance on the EntryPoint.
    /// @param account Account to query
    /// @return The available deposit in wei
    function balanceOf(address account) external view returns (uint256);

    /// @notice Withdraws part of the deposit to an address.
    /// @dev    msg.sender = the account whose deposit is debited (here the Paymaster).
    /// @param withdrawAddress Recipient of the funds
    /// @param withdrawAmount  Amount to withdraw (wei)
    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external;

    /// @notice Returns the next valid nonce for (sender, key).
    /// @dev    The ERC-4337 nonce is composite: 192 bits of "key" | 64 bits of sequence.
    ///         In V1 we always use key = 0.
    /// @param sender The SmartAccount concerned
    /// @param key    The nonce space (0 in V1)
    /// @return nonce The full nonce to put in the UserOp
    function getNonce(address sender, uint192 key) external view returns (uint256 nonce);

    /// @notice Computes the canonical hash of a UserOperation, as seen on-chain.
    /// @dev    SOURCE OF TRUTH for the signature: the client must sign THIS hash
    ///         (see the "signed hash" pitfall). In v0.8 it embeds an EIP-712 domain
    ///         (EntryPoint + chainId), hence the value of requesting it on-chain rather
    ///         than recomputing it by hand off-chain.
    /// @param userOp The UserOperation
    /// @return The userOpHash
    function getUserOpHash(PackedUserOperation calldata userOp) external view returns (bytes32);

    /// @notice Main entry point: validates then executes a batch of UserOps.
    /// @dev    This is what the bundler calls inside a real Ethereum transaction.
    /// @param ops         The batch of UserOperations (a single one in V1)
    /// @param beneficiary Address that receives the gas reimbursement (the bundler)
    function handleOps(PackedUserOperation[] calldata ops, address payable beneficiary) external;
}
