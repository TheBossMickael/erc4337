import { createWalletClient, http, getAddress, isAddress, type Hex } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';
import { config, publicClient } from './config';
import { secretQuestionAbi, secretQuestionBytecode } from './secretQuestionArtifact';

/**
 * SETUP flow backend (V2): deploys a SecretQuestionAccount for a client-derived signer address.
 *
 * The deployer key lives SERVER-SIDE (config.deployerKey) and never reaches the browser —
 * deployer != signer. The frontend only sends the ADDRESS derived from the user's answers; the
 * private key stays in the browser. We deploy with viem (no forge subprocess) using the ABI +
 * bytecode EMBEDDED at build time (see scripts/gen-artifact.js), so this is fully self-contained
 * and works on Render / for a cloner without Foundry.
 */

/**
 * Deploys SecretQuestionAccount(entryPoint, signerAddress) and returns its address.
 * @param body JSON body of POST /deploy: { signerAddress }
 */
export async function handleDeploy(body: { signerAddress?: string }): Promise<{ account: Hex }> {
  const signerAddress = body?.signerAddress;
  if (!signerAddress || !isAddress(signerAddress)) {
    throw new Error('Invalid or missing "signerAddress"');
  }
  if (!config.deployerKey) {
    throw new Error('Server not configured for deployment: DEPLOYER_PRIVATE_KEY is missing');
  }

  const deployer = privateKeyToAccount(config.deployerKey);
  const walletClient = createWalletClient({
    account: deployer,
    chain: sepolia,
    transport: http(config.rpcUrl),
  });

  console.log(`[deploy] deploying SecretQuestionAccount(signer=${getAddress(signerAddress)})`);
  const txHash = await walletClient.deployContract({
    abi: secretQuestionAbi,
    bytecode: secretQuestionBytecode,
    args: [config.entryPoint, getAddress(signerAddress)],
  });

  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
  if (!receipt.contractAddress) {
    throw new Error('Deployment failed: no contractAddress in the receipt');
  }
  const account = getAddress(receipt.contractAddress);
  console.log(`[deploy] tx ${txHash} -> account ${account} (block ${receipt.blockNumber})`);
  return { account };
}
