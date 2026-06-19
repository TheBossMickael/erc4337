// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {Paymaster} from "../src/Paymaster.sol";
import {IEntryPoint} from "../src/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "../src/interfaces/IAccount.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title IntegrationForkTest — end-to-end test against the REAL EntryPoint
/// @notice Run it against a Sepolia fork:
///   forge test --match-path test/Integration.fork.t.sol --fork-url $SEPOLIA_RPC_URL -vvv
///
/// @dev This test:
///   1. deploys SmartAccount + Paymaster IN the fork (Sepolia untouched)
///   2. funds the Paymaster on the real EntryPoint (depositTo)
///   3. builds + signs a real UserOp
///   4. calls the REAL EntryPoint.handleOps() like a bundler would
///   5. verifies the callData was executed (ETH transferred to a target)
///
/// This is THE most important validation: it exercises the real EntryPoint code, hence the
/// hash format, the packing, the prefund/paymaster, without spending any sETH.
///
/// If this file is run WITHOUT --fork-url, the EntryPoint address has no code: the tests
/// are then automatically SKIPPED (see the onlyFork modifier).
contract IntegrationForkTest is Test {
    /// @dev ERC-4337 v0.8 EntryPoint on Sepolia.
    address payable internal constant ENTRYPOINT = payable(0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108);

    IEntryPoint internal entryPoint = IEntryPoint(ENTRYPOINT);

    SmartAccount internal account;
    Paymaster internal paymaster;

    uint256 internal constant OWNER_KEY = 0xA11CE;
    address internal owner;

    address internal constant TARGET = address(0xBEEF);
    address payable internal beneficiary;

    function setUp() public {
        owner = vm.addr(OWNER_KEY);
        beneficiary = payable(makeAddr("beneficiary"));

        // We deploy our contracts in the fork (or locally if there is no fork).
        account = new SmartAccount(ENTRYPOINT, owner);
        paymaster = new Paymaster(ENTRYPOINT, owner);
    }

    /// @dev Skips the test if the EntryPoint has no code (= we are not on a fork).
    modifier onlyFork() {
        if (ENTRYPOINT.code.length == 0) {
            emit log("EntryPoint missing: test skipped (run with --fork-url $SEPOLIA_RPC_URL)");
            vm.skip(true);
            return;
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                          PACKING HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Packs two uint128 into a bytes32: [high (128 bits) | low (128 bits)].
    function _pack(uint128 high, uint128 low) internal pure returns (bytes32) {
        return bytes32((uint256(high) << 128) | uint256(low));
    }

    /// @dev Builds the v0.8 paymasterAndData field:
    ///      paymaster(20) | verificationGasLimit(16) | postOpGasLimit(16) | data(free).
    function _paymasterAndData(address pm, uint128 verifGas, uint128 postOpGas)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(pm, verifGas, postOpGas);
    }

    /*//////////////////////////////////////////////////////////////
                                THE TEST
    //////////////////////////////////////////////////////////////*/

    function test_handleOps_executesUserOp_sponsoredByPaymaster() public onlyFork {
        // --- Fund the Paymaster on the EntryPoint --------------------------
        // (LARGELY covers the max gas cost: see the "funding" pitfall)
        vm.deal(address(this), 2 ether);
        entryPoint.depositTo{value: 1 ether}(address(paymaster));
        assertEq(entryPoint.balanceOf(address(paymaster)), 1 ether, "paymaster deposit");

        // --- Fund the account for the callData's ETH transfer --------------
        // (gas is paid by the paymaster, but the VALUE sent to TARGET comes from the account)
        uint256 transferValue = 0.01 ether;
        vm.deal(address(account), 1 ether);

        // --- Build the UserOp (everything EXCEPT the signature) ------------
        PackedUserOperation memory userOp;
        userOp.sender = address(account);
        userOp.nonce = entryPoint.getNonce(address(account), 0); // key = 0 in V1
        userOp.initCode = ""; // account already deployed: no factory in V1
        // callData = call to execute(TARGET, transferValue, "")
        userOp.callData = abi.encodeCall(SmartAccount.execute, (TARGET, transferValue, ""));
        // accountGasLimits = verificationGasLimit | callGasLimit
        userOp.accountGasLimits = _pack(300_000, 300_000);
        userOp.preVerificationGas = 100_000;
        // gasFees = maxPriorityFeePerGas | maxFeePerGas (generous for the fork)
        userOp.gasFees = _pack(uint128(2 gwei), uint128(uint256(block.basefee) + 20 gwei));
        // paymasterAndData: we designate our Paymaster as sponsor
        userOp.paymasterAndData = _paymasterAndData(address(paymaster), 200_000, 100_000);

        // --- Sign: get the CANONICAL hash then sign with personal_sign ------
        // SOURCE OF TRUTH: we ask the real EntryPoint for the hash (the "hash" pitfall).
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_KEY, digest);
        userOp.signature = abi.encodePacked(r, s, v);

        // --- Submit like a bundler would -----------------------------------
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        uint256 targetBalanceBefore = TARGET.balance;
        entryPoint.handleOps(ops, beneficiary);

        // --- Verify the on-chain effect ------------------------------------
        assertEq(TARGET.balance - targetBalanceBefore, transferValue, "callData executed: ETH received");
        // The beneficiary (bundler) was indeed reimbursed in gas by the paymaster deposit.
        assertGt(beneficiary.balance, 0, "beneficiary reimbursed");
        console2.log("Beneficiary reimbursement (wei):", beneficiary.balance);
    }
}
