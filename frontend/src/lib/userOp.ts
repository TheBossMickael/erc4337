import { numberToHex, concat, getAddress, type Hex } from 'viem';

/**
 * PackedUserOperation (internal, strongly-typed form). Ported from the bundler so the frontend
 * builds UserOps identically. nonce / preVerificationGas are bigint; everything else is Hex.
 */
export interface PackedUserOperation {
  sender: Hex;
  nonce: bigint;
  initCode: Hex;
  callData: Hex;
  accountGasLimits: Hex;
  preVerificationGas: bigint;
  gasFees: Hex;
  paymasterAndData: Hex;
  signature: Hex;
}

/** Wire form (JSON-RPC): EVERYTHING as hex strings, because JSON has no bigint. */
export interface UserOperationHex {
  sender: Hex;
  nonce: Hex;
  initCode: Hex;
  callData: Hex;
  accountGasLimits: Hex;
  preVerificationGas: Hex;
  gasFees: Hex;
  paymasterAndData: Hex;
  signature: Hex;
}

/**
 * Packs two 128-bit values into a bytes32: [high (128) | low (128)].
 *   accountGasLimits = pack(verificationGasLimit, callGasLimit)
 *   gasFees          = pack(maxPriorityFeePerGas, maxFeePerGas)
 */
export function packUint128Pair(high: bigint, low: bigint): Hex {
  if (high > 2n ** 128n - 1n || low > 2n ** 128n - 1n) {
    throw new Error('packUint128Pair: value > uint128');
  }
  return numberToHex((high << 128n) | low, { size: 32 });
}

/**
 * Builds the v0.8 paymasterAndData field:
 *   paymaster(20) | paymasterVerificationGasLimit(16) | paymasterPostOpGasLimit(16) | data
 * Pass paymaster = '0x' for a UserOp WITHOUT a sponsor.
 */
export function buildPaymasterAndData(
  paymaster: Hex,
  verificationGasLimit: bigint,
  postOpGasLimit: bigint,
  data: Hex = '0x',
): Hex {
  if (paymaster === '0x' || paymaster.length < 42) {
    return '0x';
  }
  return concat([
    getAddress(paymaster),
    numberToHex(verificationGasLimit, { size: 16 }),
    numberToHex(postOpGasLimit, { size: 16 }),
    data,
  ]);
}

/** Converts the internal (bigint) form to the wire (hex) form for the JSON-RPC payload. */
export function toHexOp(op: PackedUserOperation): UserOperationHex {
  return {
    sender: op.sender,
    nonce: numberToHex(op.nonce),
    initCode: op.initCode,
    callData: op.callData,
    accountGasLimits: op.accountGasLimits,
    preVerificationGas: numberToHex(op.preVerificationGas),
    gasFees: op.gasFees,
    paymasterAndData: op.paymasterAndData,
    signature: op.signature,
  };
}
