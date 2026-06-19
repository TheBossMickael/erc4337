// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {Paymaster} from "../src/Paymaster.sol";
import {Counter} from "../src/Counter.sol";
import {IEntryPoint} from "../src/interfaces/IEntryPoint.sol";

/// @title Deploy — deploys SmartAccount + Paymaster + Counter and funds the Paymaster
/// @notice Reads parameters from contracts/.env:
///           ENTRYPOINT_ADDRESS  : EntryPoint v0.8 (0x4337...108 on Sepolia)
///           OWNER_ADDRESS       : SmartAccount owner (signs the UserOps)
///           PRIVATE_KEY         : DEPLOYER key (pays the gas + the Paymaster deposit)
///           PAYMASTER_DEPOSIT   : amount to deposit for the Paymaster (in wei)
///
/// @dev Usage:
///   Simulation (no tx sent):
///     forge script script/Deploy.s.sol --rpc-url sepolia
///   Real deployment:
///     forge script script/Deploy.s.sol --rpc-url sepolia --broadcast
///
///   After deployment, copy the printed addresses into bundler/.env
///   (SMART_ACCOUNT_ADDRESS, PAYMASTER_ADDRESS and COUNTER_ADDRESS).
contract Deploy is Script {
    function run() external returns (SmartAccount account, Paymaster paymaster, Counter counter) {
        address entryPoint = vm.envAddress("ENTRYPOINT_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        uint256 paymasterDeposit = vm.envUint("PAYMASTER_DEPOSIT");

        vm.startBroadcast(deployerKey);

        // 1. The user's account
        account = new SmartAccount(entryPoint, owner);

        // 2. The gas sponsor
        paymaster = new Paymaster(entryPoint, owner);

        // 3. The demo witness contract (UserOps target: increment())
        counter = new Counter();

        // 4. Fund the Paymaster ON the EntryPoint (not on the contract itself).
        //    The ETH comes from the deployer (the broadcast). This is the deposit the
        //    EntryPoint will draw from to reimburse the bundler.
        IEntryPoint(entryPoint).depositTo{value: paymasterDeposit}(address(paymaster));

        vm.stopBroadcast();

        console2.log("EntryPoint           :", entryPoint);
        console2.log("Owner                :", owner);
        console2.log("SmartAccount deployed:", address(account));
        console2.log("Paymaster deployed   :", address(paymaster));
        console2.log("Counter deployed     :", address(counter));
        console2.log("Paymaster deposit(wei):", paymasterDeposit);
    }
}
