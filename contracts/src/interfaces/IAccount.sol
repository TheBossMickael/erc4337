// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct PackedUserOperation {
    address sender;              // address of the SmartAccount
    uint256 nonce;               // anti-replay: 192-bit key | 64-bit sequence
    bytes initCode;              // factory(20 bytes) + factoryData — empty if already deployed
    bytes callData;              // what the SmartAccount must execute
    bytes32 accountGasLimits;    // uint128(verificationGasLimit) | uint128(callGasLimit)
    uint256 preVerificationGas;  // off-chain gas: bundler compensation
    bytes32 gasFees;             // uint128(maxPriorityFeePerGas) | uint128(maxFeePerGas)
    bytes paymasterAndData;      // paymaster(20) | verifGasLimit(16) | postOpGasLimit(16) | data
    bytes signature;             // validated by validateUserOp() — free format, up to us
}

interface IAccount {
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        returns (uint256 validationData);
}
