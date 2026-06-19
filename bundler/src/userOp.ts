import { numberToHex, concat, getAddress, isHex, type Hex } from 'viem';

/**
 * PackedUserOperation on the TypeScript side ("internal" format, strongly typed).
 * - nonce / preVerificationGas are bigint (256-bit integers).
 * - all other fields are Hex ("0x..." strings).
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

/**
 * Same struct but in "wire" format (JSON-RPC): EVERYTHING as hex strings, because JSON
 * cannot represent bigint. This is what travels between the client and the bundler.
 */
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
 * Used for accountGasLimits and gasFees.
 *   accountGasLimits = pack(verificationGasLimit, callGasLimit)
 *   gasFees          = pack(maxPriorityFeePerGas, maxFeePerGas)
 */
export function packUint128Pair(high: bigint, low: bigint): Hex {
  if (high > (2n ** 128n - 1n) || low > (2n ** 128n - 1n)) {
    throw new Error('packUint128Pair: value > uint128');
  }
  return numberToHex((high << 128n) | low, { size: 32 });
}

/**
 * Builds the v0.8 paymasterAndData field:
 *   paymaster(20) | paymasterVerificationGasLimit(16) | paymasterPostOpGasLimit(16) | data
 * Pass paymaster = '0x' (empty) for a UserOp WITHOUT a sponsor.
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

/** Converts the wire format (hex) to the internal format (bigint). */
export function toPacked(op: UserOperationHex): PackedUserOperation {
  return {
    sender: getAddress(op.sender),
    nonce: BigInt(op.nonce),
    initCode: op.initCode,
    callData: op.callData,
    accountGasLimits: op.accountGasLimits,
    preVerificationGas: BigInt(op.preVerificationGas),
    gasFees: op.gasFees,
    paymasterAndData: op.paymasterAndData,
    signature: op.signature,
  };
}

/** Converts the internal format (bigint) to the wire format (hex) for the JSON payload. */
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

/**
 * Basic SHAPE validation of an incoming UserOp (V1: we don't check opcodes,
 * see the ERC-7562 limitation). We just ensure required fields exist and are hex.
 */
export function assertValidUserOpHex(op: UserOperationHex): void {
  const fields: (keyof UserOperationHex)[] = [
    'sender', 'nonce', 'initCode', 'callData', 'accountGasLimits',
    'preVerificationGas', 'gasFees', 'paymasterAndData', 'signature',
  ];
  for (const f of fields) {
    if (op[f] === undefined || op[f] === null) {
      throw new Error(`Invalid UserOp: missing field "${f}"`);
    }
    if (!isHex(op[f])) {
      throw new Error(`Invalid UserOp: field "${f}" is not hexadecimal`);
    }
  }
}
