// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AccountFactory} from "../src/AccountFactory.sol";
import {PasskeyAccount} from "../src/PasskeyAccount.sol";

/// @title AccountFactoryTest — unit tests for the CREATE2 counterfactual factory (local EVM).
/// @dev These tests need NO valid P-256 signature: the factory only deploys and the account only
///      stores (x, y) in its constructor. We use arbitrary key coordinates. Signature validation is
///      covered separately in PasskeyAccount.t.sol (with a locked WebAuthn vector).
contract AccountFactoryTest is Test {
    AccountFactory internal factory;

    // Sepolia EntryPoint v0.8 address — only stored/echoed here, never called in these tests.
    address internal constant ENTRYPOINT = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

    // Arbitrary but fixed P-256 public-key coordinates (not a real key — never signature-checked here).
    bytes32 internal constant X = bytes32(uint256(0x1111));
    bytes32 internal constant Y = bytes32(uint256(0x2222));

    function setUp() public {
        factory = new AccountFactory(ENTRYPOINT);
    }

    /*//////////////////////////////////////////////////////////////
                          COUNTERFACTUAL ADDRESS
    //////////////////////////////////////////////////////////////*/

    function test_getAddress_matchesDeployedAddress() public {
        address predicted = factory.getAddress(X, Y, 0);
        assertEq(predicted.code.length, 0, "predicted address is empty before deployment");

        PasskeyAccount account = factory.createAccount(X, Y, 0);

        assertEq(address(account), predicted, "deployed address == getAddress()");
        assertGt(predicted.code.length, 0, "account has code after deployment");
    }

    function test_getAddress_isPure_stableAcrossCalls() public view {
        assertEq(factory.getAddress(X, Y, 0), factory.getAddress(X, Y, 0), "getAddress is deterministic");
    }

    /*//////////////////////////////////////////////////////////////
                               IDEMPOTENCE
    //////////////////////////////////////////////////////////////*/

    /// @dev The EntryPoint calls createAccount on the first UserOp; a retry/duplicate must NOT revert.
    function test_createAccount_isIdempotent() public {
        PasskeyAccount first = factory.createAccount(X, Y, 0);
        PasskeyAccount second = factory.createAccount(X, Y, 0); // must not revert on CREATE2 collision

        assertEq(address(first), address(second), "second call returns the same account");
    }

    /*//////////////////////////////////////////////////////////////
                              DETERMINISM
    //////////////////////////////////////////////////////////////*/

    function test_differentKeys_giveDifferentAddresses() public view {
        address a = factory.getAddress(X, Y, 0);
        address b = factory.getAddress(bytes32(uint256(0x3333)), Y, 0);
        assertTrue(a != b, "different pubkey => different address");
    }

    function test_differentSalt_giveDifferentAddresses() public view {
        assertTrue(factory.getAddress(X, Y, 0) != factory.getAddress(X, Y, 1), "different salt => different address");
    }

    /*//////////////////////////////////////////////////////////////
                          DEPLOYED ACCOUNT STATE
    //////////////////////////////////////////////////////////////*/

    function test_deployedAccount_storesKeyAndEntryPoint() public {
        PasskeyAccount account = factory.createAccount(X, Y, 0);

        (bytes32 x, bytes32 y) = account.pubKey();
        assertEq(x, X, "stored pubKeyX");
        assertEq(y, Y, "stored pubKeyY");
        assertEq(account.entryPoint(), ENTRYPOINT, "stored entryPoint");
    }

    function test_factory_exposesEntryPoint() public view {
        assertEq(factory.entryPoint(), ENTRYPOINT);
    }
}
