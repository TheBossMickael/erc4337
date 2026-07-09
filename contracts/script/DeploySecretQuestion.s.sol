// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {SecretQuestionAccount} from "../src/SecretQuestionAccount.sol";
import {Paymaster} from "../src/Paymaster.sol";
import {Counter} from "../src/Counter.sol";
import {IEntryPoint} from "../src/interfaces/IEntryPoint.sol";

/// @title DeploySecretQuestion — deploys the V2 demo (auth by knowledge)
/// @notice Deploys a SecretQuestionAccount + a fresh Paymaster + Counter and funds the Paymaster.
///         Self-contained: it does NOT touch the V1 deployment, and uses its OWN Paymaster so the
///         V1 deposit is never drained.
///
/// @dev Reads parameters from contracts/.env:
///        ENTRYPOINT_ADDRESS : EntryPoint v0.8 (0x4337...108 on Sepolia)
///        SIGNER_ADDRESS     : address DERIVED from the secret answers (deployer != signer!)
///        PRIVATE_KEY        : DEPLOYER key (pays the gas + the Paymaster deposit)
///        PAYMASTER_DEPOSIT  : amount to deposit for the Paymaster (in wei)
///
///      Usage:
///        Simulation:       forge script script/DeploySecretQuestion.s.sol --rpc-url sepolia
///        Real deployment:  forge script script/DeploySecretQuestion.s.sol --rpc-url sepolia --broadcast
///
///      After deployment, copy the printed addresses into frontend/.env (VITE_DEMO_ACCOUNT_ADDRESS,
///      VITE_PAYMASTER_ADDRESS, VITE_COUNTER_ADDRESS) and bundler/.env.
contract DeploySecretQuestion is Script {
    function run() external returns (SecretQuestionAccount account, Paymaster paymaster, Counter counter) {
        address entryPoint = vm.envAddress("ENTRYPOINT_ADDRESS");
        address signer = vm.envAddress("SIGNER_ADDRESS");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        uint256 paymasterDeposit = vm.envUint("PAYMASTER_DEPOSIT");

        vm.startBroadcast(deployerKey);

        // 1. The V2 account: its signer is the address derived from the answers (never the deployer).
        account = new SecretQuestionAccount(entryPoint, signer);

        // 2. A fresh gas sponsor, owned by the DEPLOYER (who can later withdraw the deposit).
        //    The owner is intentionally NOT the derived signer (which comes from public answers).
        paymaster = new Paymaster(entryPoint, vm.addr(deployerKey));

        // 3. The demo witness contract (UserOps target: increment()).
        counter = new Counter();

        // 4. Fund the Paymaster ON the EntryPoint (the deposit the EntryPoint draws from to
        //    reimburse the bundler). Drains per UserOp -> top up via paymaster.deposit().
        IEntryPoint(entryPoint).depositTo{value: paymasterDeposit}(address(paymaster));

        vm.stopBroadcast();

        console2.log("EntryPoint            :", entryPoint);
        console2.log("Signer (derived)      :", signer);
        console2.log("SecretQuestionAccount :", address(account));
        console2.log("Paymaster             :", address(paymaster));
        console2.log("Counter               :", address(counter));
        console2.log("Paymaster deposit(wei):", paymasterDeposit);
    }
}
