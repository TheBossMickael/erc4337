// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PackedUserOperation} from "./IAccount.sol";

/// @title IPaymaster — interface an ERC-4337 Paymaster contract must implement
/// @notice A Paymaster agrees to PAY the gas on behalf of the user.
///         The EntryPoint queries it in two phases:
///           1. validatePaymasterUserOp() during the verification loop ("do you pay?")
///           2. postOp() after execution ("here is the real cost, reconcile it")
interface IPaymaster {
    /// @notice Result of the execution, passed to postOp by the EntryPoint.
    enum PostOpMode {
        opSucceeded, // the callData execution succeeded
        opReverted   // the execution reverted — the Paymaster STILL pays the gas
    }

    /// @notice Decides whether the Paymaster sponsors this UserOp.
    /// @dev    MUST check msg.sender == EntryPoint.
    ///         Like validateUserOp on the account side: never revert to "refuse",
    ///         return a non-zero validationData. Revert only on a fatal error.
    /// @param userOp     The UserOperation to sponsor
    /// @param userOpHash Hash of the UserOp (computed by the EntryPoint)
    /// @param maxCost    Max cost in wei the EntryPoint might charge
    /// @return context        Opaque data passed to postOp (empty = postOp not called)
    /// @return validationData  0 = accepted (see packing aggregator|validUntil|validAfter)
    function validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        external
        returns (bytes memory context, uint256 validationData);

    /// @notice Called after execution to reconcile the real cost.
    /// @dev    MUST check msg.sender == EntryPoint.
    ///         Only called if validatePaymasterUserOp returned a non-empty context.
    /// @param mode                  Result of the execution (success / revert)
    /// @param context               Data returned by validatePaymasterUserOp
    /// @param actualGasCost         Real cost of the gas already consumed (wei)
    /// @param actualUserOpFeePerGas Effective gas price for this UserOp (new in v0.8)
    function postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)
        external;
}
