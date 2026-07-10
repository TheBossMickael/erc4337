/**
 * Minimal ABIs used by the frontend (read-only on-chain calls + calldata encoding).
 * The EntryPoint tuple field ORDER and TYPES must match the Solidity PackedUserOperation EXACTLY,
 * otherwise getUserOpHash returns a wrong hash and the signature fails (AA24).
 */

export const entryPointAbi = [
  {
    type: 'function',
    name: 'getUserOpHash',
    stateMutability: 'view',
    inputs: [
      {
        name: 'userOp',
        type: 'tuple',
        components: [
          { name: 'sender', type: 'address' },
          { name: 'nonce', type: 'uint256' },
          { name: 'initCode', type: 'bytes' },
          { name: 'callData', type: 'bytes' },
          { name: 'accountGasLimits', type: 'bytes32' },
          { name: 'preVerificationGas', type: 'uint256' },
          { name: 'gasFees', type: 'bytes32' },
          { name: 'paymasterAndData', type: 'bytes' },
          { name: 'signature', type: 'bytes' },
        ],
      },
    ],
    outputs: [{ type: 'bytes32' }],
  },
  {
    type: 'function',
    name: 'getNonce',
    stateMutability: 'view',
    inputs: [
      { name: 'sender', type: 'address' },
      { name: 'key', type: 'uint192' },
    ],
    outputs: [{ name: 'nonce', type: 'uint256' }],
  },
] as const;

/** SmartAccount/SecretQuestionAccount.execute — what the EntryPoint calls on the account. */
export const executeAbi = [
  {
    type: 'function',
    name: 'execute',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'dest', type: 'address' },
      { name: 'value', type: 'uint256' },
      { name: 'func', type: 'bytes' },
    ],
    outputs: [],
  },
] as const;

/** Counter — the final target of the demo action. */
export const counterAbi = [
  { type: 'function', name: 'increment', stateMutability: 'nonpayable', inputs: [], outputs: [] },
  { type: 'function', name: 'count', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
] as const;

/**
 * AccountFactory — used to (1) READ the counterfactual account address off-chain (getAddress) and
 * (2) ENCODE the createAccount calldata that goes into a first UserOp's initCode.
 */
export const factoryAbi = [
  {
    type: 'function',
    name: 'getAddress',
    stateMutability: 'view',
    inputs: [
      { name: 'x', type: 'bytes32' },
      { name: 'y', type: 'bytes32' },
      { name: 'salt', type: 'uint256' },
    ],
    outputs: [{ type: 'address' }],
  },
  {
    type: 'function',
    name: 'createAccount',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'x', type: 'bytes32' },
      { name: 'y', type: 'bytes32' },
      { name: 'salt', type: 'uint256' },
    ],
    outputs: [{ type: 'address' }],
  },
] as const;
