import '../loadEnv';
import {
  createPublicClient,
  http,
  encodeFunctionData,
  getAddress,
  parseGwei,
  type Hex,
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';
import { entryPointAbi } from '../entryPoint';
import {
  packUint128Pair,
  buildPaymasterAndData,
  toHexOp,
  type PackedUserOperation,
} from '../userOp';

/**
 * TEST CLIENT — plays the role a frontend (or a curl) would.
 * Demo: make the SmartAccount CALL Counter.increment() via a UserOp sponsored by the
 * Paymaster (so the user pays no gas and signs no transaction).
 *
 * Run: `npx ts-node src/client/sendUserOp.ts`
 * (after deployment + bundler running + bundler/.env filled).
 */

const RPC = process.env.SEPOLIA_RPC_URL as string;
const ENTRYPOINT = getAddress(process.env.ENTRYPOINT_ADDRESS as string);
const ACCOUNT = getAddress(process.env.SMART_ACCOUNT_ADDRESS as string);
const PAYMASTER = getAddress(process.env.PAYMASTER_ADDRESS as string);
const COUNTER = getAddress(process.env.COUNTER_ADDRESS as string);
const OWNER_KEY = process.env.OWNER_PRIVATE_KEY as Hex;
const BUNDLER_URL = `http://localhost:${process.env.PORT ?? 3000}`;

/** Minimal ABI of SmartAccount.execute (what the EntryPoint calls on the account). */
const executeAbi = [
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

/** Counter ABI (the final target of the action). */
const counterAbi = [
  { type: 'function', name: 'increment', stateMutability: 'nonpayable', inputs: [], outputs: [] },
  { type: 'function', name: 'count', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
] as const;

async function main(): Promise<void> {
  const publicClient = createPublicClient({ chain: sepolia, transport: http(RPC) });
  const owner = privateKeyToAccount(OWNER_KEY);

  // Counter value BEFORE (to prove the effect).
  const countBefore = (await publicClient.readContract({
    address: COUNTER,
    abi: counterAbi,
    functionName: 'count',
  })) as bigint;

  // --- Build the TWO levels of calldata ---------------------------------
  // func = INNER calldata: call to increment() (just the selector, no args)
  const func = encodeFunctionData({ abi: counterAbi, functionName: 'increment' });
  // callData = what the EntryPoint calls on the SmartAccount: execute(counter, 0, func)
  // value = 0: increment() needs no ETH → the SmartAccount doesn't even need funding.
  const callData = encodeFunctionData({
    abi: executeAbi,
    functionName: 'execute',
    args: [COUNTER, 0n, func],
  });

  // --- Current account nonce (nonce space key = 0 in V1) -----------------
  const nonce = (await publicClient.readContract({
    address: ENTRYPOINT,
    abi: entryPointAbi,
    functionName: 'getNonce',
    args: [ACCOUNT, 0n],
  })) as bigint;

  // --- Build the UserOp (empty signature for now) ------------------------
  const userOp: PackedUserOperation = {
    sender: ACCOUNT,
    nonce,
    initCode: '0x', // account already deployed: no factory in V1
    callData,
    // accountGasLimits = verificationGasLimit | callGasLimit (generous, see V1 limitations)
    accountGasLimits: packUint128Pair(300_000n, 300_000n),
    preVerificationGas: 100_000n,
    // gasFees = maxPriorityFeePerGas | maxFeePerGas
    gasFees: packUint128Pair(parseGwei('2'), parseGwei('30')),
    // paymasterAndData: we designate the Paymaster to sponsor the gas
    paymasterAndData: buildPaymasterAndData(PAYMASTER, 200_000n, 100_000n),
    signature: '0x',
  };

  // --- Sign the CANONICAL hash (fetched from the real EntryPoint) --------
  const userOpHash = (await publicClient.readContract({
    address: ENTRYPOINT,
    abi: entryPointAbi,
    functionName: 'getUserOpHash',
    args: [userOp],
  })) as Hex;

  // signMessage({ raw }) applies the EIP-191 prefix ("\x19Ethereum Signed Message:\n32"
  // + hash) BEFORE signing — the exact equivalent of MessageHashUtils.toEthSignedMessageHash
  // on the contract side. This is the key invariant: client and contract apply the SAME prefix.
  userOp.signature = await owner.signMessage({ message: { raw: userOpHash } });

  console.log('Counter before:', countBefore.toString());
  console.log('UserOpHash    :', userOpHash);
  console.log('Signed by     :', owner.address);

  // --- Send to the bundler via JSON-RPC ----------------------------------
  const body = {
    jsonrpc: '2.0',
    id: 1,
    method: 'eth_sendUserOperation',
    params: [toHexOp(userOp), ENTRYPOINT],
  };

  const res = await fetch(`${BUNDLER_URL}/rpc`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const json = await res.json();
  console.log('Bundler response:', JSON.stringify(json, null, 2));

  // The handler waits for the receipt before responding → the tx is mined here.
  const countAfter = (await publicClient.readContract({
    address: COUNTER,
    abi: counterAbi,
    functionName: 'count',
  })) as bigint;
  console.log(`Counter after : ${countAfter.toString()}  (${countBefore} -> ${countAfter})`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
