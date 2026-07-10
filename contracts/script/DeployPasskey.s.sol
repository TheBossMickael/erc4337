// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {AccountFactory} from "../src/AccountFactory.sol";
import {Paymaster} from "../src/Paymaster.sol";
import {Counter} from "../src/Counter.sol";
import {IEntryPoint} from "../src/interfaces/IEntryPoint.sol";

/// @title DeployPasskey — deploys the V3 demo (passkeys / WebAuthn P-256 + counterfactual factory)
/// @notice Deploys the AccountFactory + a fresh Paymaster + Counter and funds the Paymaster.
///         NO account is deployed here: PasskeyAccounts are created lazily, per passkey, inside each
///         user's FIRST UserOp (via the factory + `initCode`). Self-contained: does NOT touch the V1
///         or V2 deployments, and uses its OWN Paymaster so those deposits are never drained.
///
/// @dev Reads parameters from contracts/.env:
///        ENTRYPOINT_ADDRESS : EntryPoint v0.8 (0x4337...108 on Sepolia)
///        PRIVATE_KEY        : DEPLOYER key (pays the gas + the Paymaster deposit; also Paymaster owner)
///        PAYMASTER_DEPOSIT  : amount to deposit for the Paymaster (wei). Fund GENEROUSLY: the first
///                             UserOp of each account also pays for that account's CREATE2 deployment.
///
///      Usage:
///        Simulation:      forge script script/DeployPasskey.s.sol --rpc-url sepolia
///        Real deployment: forge script script/DeployPasskey.s.sol --rpc-url sepolia --broadcast --verify
///
///      After deployment, copy the printed addresses into render.yaml / the env vars
///      (VITE_FACTORY_ADDRESS, VITE_PAYMASTER_ADDRESS, VITE_COUNTER_ADDRESS) and bundler envs.
contract DeployPasskey is Script {
    function run() external returns (AccountFactory factory, Paymaster paymaster, Counter counter) {
        address entryPoint = vm.envAddress("ENTRYPOINT_ADDRESS");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        uint256 paymasterDeposit = vm.envUint("PAYMASTER_DEPOSIT");

        vm.startBroadcast(deployerKey);

        // 1. The CREATE2 factory — accounts are deployed on the fly from users' first UserOps.
        factory = new AccountFactory(entryPoint);

        // 2. A fresh gas sponsor, owned by the DEPLOYER (who can later withdraw the deposit).
        paymaster = new Paymaster(entryPoint, vm.addr(deployerKey));

        // 3. The demo witness contract (UserOps target: increment()).
        counter = new Counter();

        // 4. Fund the Paymaster ON the EntryPoint. The first UserOp per account is heavier (it also
        //    deploys the account), so size this generously. Top up later via paymaster.deposit().
        IEntryPoint(entryPoint).depositTo{value: paymasterDeposit}(address(paymaster));

        vm.stopBroadcast();

        console2.log("EntryPoint            :", entryPoint);
        console2.log("AccountFactory        :", address(factory));
        console2.log("Paymaster             :", address(paymaster));
        console2.log("Counter               :", address(counter));
        console2.log("Paymaster deposit(wei):", paymasterDeposit);
    }
}
