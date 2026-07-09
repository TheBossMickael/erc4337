// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SecretQuestionAccount} from "../src/SecretQuestionAccount.sol";
import {BaseAccount} from "../src/BaseAccount.sol";
import {PackedUserOperation} from "../src/interfaces/IAccount.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {MockEntryPoint} from "./mocks/MockEntryPoint.sol";

/// @title SecretQuestionAccountTest — unit tests for SecretQuestionAccount (local EVM, instant)
/// @dev We play the EntryPoint via MockEntryPoint (vm.prank). The "signer" key models the key the
///      frontend re-derives from the secret answers: here we use an arbitrary test key, since
///      validation only ever sees the derived ADDRESS. The TS<->Solidity demo-answer cross-check
///      lives alongside the derivation lib (frontend/src/lib/derive.test.ts).
contract SecretQuestionAccountTest is Test {
    SecretQuestionAccount internal account;
    MockEntryPoint internal entryPoint;

    // Models the key the frontend derives from the answers. vm.addr derives its address.
    uint256 internal constant SIGNER_KEY = 0x5EC4E7;
    address internal signer;

    address internal constant TARGET = address(0xBEEF);

    // Demo vector: key/address derived from the PUBLIC demo answers ("rex","paris","inception")
    // via frontend/src/lib/derive.ts. Locked here to cross-check the off-chain KDF against on-chain
    // validation — the V2 analog of V1's signed-hash invariant.
    uint256 internal constant DEMO_SIGNER_KEY = 0x34dbb35f6459589466de132a3b780186ad002c3464057af4c2f00427e91968dd;
    address internal constant DEMO_SIGNER_ADDR = 0x6791C67E22f99Cf7D019f6e5D4009E9BDB853ACa;

    function setUp() public {
        signer = vm.addr(SIGNER_KEY);
        entryPoint = new MockEntryPoint();
        account = new SecretQuestionAccount(address(entryPoint), signer);
    }

    /// @dev Builds a UserOp signed with `key`, reproducing EXACTLY what the contract expects:
    ///      sign toEthSignedMessageHash(userOpHash) (personal_sign convention).
    function _userOpSignedBy(bytes32 userOpHash, uint256 key)
        internal
        pure
        returns (PackedUserOperation memory userOp)
    {
        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        userOp.signature = abi.encodePacked(r, s, v);
    }

    /*//////////////////////////////////////////////////////////////
                                VALIDATION
    //////////////////////////////////////////////////////////////*/

    function test_validateUserOp_validSignature_returnsZero() public {
        bytes32 userOpHash = keccak256("some userop");
        PackedUserOperation memory userOp = _userOpSignedBy(userOpHash, SIGNER_KEY);

        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 0, "derived-key signature => 0");
    }

    function test_validateUserOp_wrongSigner_returnsOne() public {
        bytes32 userOpHash = keccak256("some userop");
        uint256 attackerKey = 0xBAD; // wrong answers => wrong derived key
        PackedUserOperation memory userOp = _userOpSignedBy(userOpHash, attackerKey);

        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 1, "wrong answers (wrong key) => 1, without reverting");
    }

    function test_validateUserOp_malformedSignature_returnsOneNoRevert() public {
        bytes32 userOpHash = keccak256("some userop");
        PackedUserOperation memory userOp;
        userOp.signature = hex"1234"; // too short / invalid

        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 1, "malformed signature => 1, never reverts");
    }

    function test_validateUserOp_notFromEntryPoint_reverts() public {
        bytes32 userOpHash = keccak256("some userop");
        PackedUserOperation memory userOp = _userOpSignedBy(userOpHash, SIGNER_KEY);

        vm.prank(address(0xDEAD));
        vm.expectRevert(BaseAccount.BaseAccount__NotFromEntryPoint.selector);
        account.validateUserOp(userOp, userOpHash, 0);
    }

    function test_validateUserOp_paysPrefund() public {
        bytes32 userOpHash = keccak256("some userop");
        PackedUserOperation memory userOp = _userOpSignedBy(userOpHash, SIGNER_KEY);

        vm.deal(address(account), 1 ether);
        uint256 missing = 0.3 ether;

        vm.prank(address(entryPoint));
        account.validateUserOp(userOp, userOpHash, missing);

        assertEq(entryPoint.balanceOf(address(account)), missing, "prefund received by the EntryPoint");
    }

    /*//////////////////////////////////////////////////////////////
                                EXECUTION
    //////////////////////////////////////////////////////////////*/

    function test_execute_transfersEth() public {
        vm.deal(address(account), 1 ether);

        vm.prank(address(entryPoint));
        account.execute(TARGET, 0.5 ether, "");

        assertEq(TARGET.balance, 0.5 ether, "ETH transferred to the target");
    }

    function test_execute_bySigner_isAllowed() public {
        vm.deal(address(account), 1 ether);

        vm.prank(signer);
        account.execute(TARGET, 0.1 ether, "");

        assertEq(TARGET.balance, 0.1 ether, "the derived signer can drive the account directly");
    }

    function test_execute_notFromEntryPointOrOwner_reverts() public {
        vm.deal(address(account), 1 ether);

        vm.prank(address(0xDEAD));
        vm.expectRevert(BaseAccount.BaseAccount__NotFromEntryPointOrOwner.selector);
        account.execute(TARGET, 0.1 ether, "");
    }

    function test_executeBatch_runsAllCalls() public {
        vm.deal(address(account), 1 ether);

        address[] memory dest = new address[](2);
        uint256[] memory value = new uint256[](2);
        bytes[] memory func = new bytes[](2);
        dest[0] = address(0xAAA1);
        dest[1] = address(0xAAA2);
        value[0] = 0.1 ether;
        value[1] = 0.2 ether;
        func[0] = "";
        func[1] = "";

        vm.prank(address(entryPoint));
        account.executeBatch(dest, value, func);

        assertEq(address(0xAAA1).balance, 0.1 ether);
        assertEq(address(0xAAA2).balance, 0.2 ether);
    }

    function test_executeBatch_lengthMismatch_reverts() public {
        address[] memory dest = new address[](2);
        uint256[] memory value = new uint256[](1);
        bytes[] memory func = new bytes[](2);

        vm.prank(address(entryPoint));
        vm.expectRevert(BaseAccount.BaseAccount__WrongArrayLengths.selector);
        account.executeBatch(dest, value, func);
    }

    /*//////////////////////////////////////////////////////////////
                              DEPOSIT & GETTERS
    //////////////////////////////////////////////////////////////*/

    function test_addDeposit_creditsEntryPoint() public {
        vm.deal(address(this), 1 ether);
        account.addDeposit{value: 0.4 ether}();
        assertEq(account.getDeposit(), 0.4 ether);
    }

    function test_getters() public view {
        assertEq(account.signerAddress(), signer);
        assertEq(account.entryPoint(), address(entryPoint));
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CHECK (TS <-> SOLIDITY)
    //////////////////////////////////////////////////////////////*/

    /// @dev Ties the off-chain derivation to on-chain validation: an account whose signer is the
    ///      frontend-derived demo address accepts a UserOp signed by the frontend-derived demo key.
    ///      If frontend/src/lib/derive.ts ever changes, this test (and the TS regression vector)
    ///      break together — exactly what we want.
    function test_demoVector_crossChecksFrontendDerivation() public {
        // Sanity: the locked key and address are consistent (key -> address).
        assertEq(vm.addr(DEMO_SIGNER_KEY), DEMO_SIGNER_ADDR, "demo key/address consistent");

        // An account whose signer is the frontend-derived demo address...
        SecretQuestionAccount demoAccount = new SecretQuestionAccount(address(entryPoint), DEMO_SIGNER_ADDR);

        // ...validates a UserOp signed by the frontend-derived demo key (returns 0).
        bytes32 userOpHash = keccak256("demo userop");
        PackedUserOperation memory userOp = _userOpSignedBy(userOpHash, DEMO_SIGNER_KEY);

        vm.prank(address(entryPoint));
        assertEq(demoAccount.validateUserOp(userOp, userOpHash, 0), 0, "frontend-derived key validates on-chain");
    }
}
