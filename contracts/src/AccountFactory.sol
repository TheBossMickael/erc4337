// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PasskeyAccount} from "./PasskeyAccount.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/// @title AccountFactory
/// @notice CREATE2 factory for PasskeyAccount — enables counterfactual (lazy) deployment (V3).
/// @dev ERC-4337 flow: the account address is computed off-chain BEFORE any deployment
///      (`getAddress`), and the real deployment is bundled into the account's FIRST UserOp via
///      `initCode` (= this factory's address ‖ `createAccount` calldata). The canonical EntryPoint
///      (its internal SenderCreator) calls `createAccount` automatically when `sender` has no code,
///      right before `validateUserOp`. This replaces V2's `POST /deploy` + server deployer key.
///
///      IDEMPOTENT: the EntryPoint calls `createAccount` on the first UserOp; if the account already
///      exists at the deterministic address (e.g. a retried/duplicate op), we return it instead of
///      reverting on the CREATE2 collision.
///
///      No `msg.sender` check: this is a public factory (like eth-infinitism's SimpleAccountFactory),
///      so the SenderCreator-vs-EntryPoint caller distinction is irrelevant here. Deploys the account
///      contract DIRECTLY via CREATE2 (no ERC-1967 proxy) — simpler, at the cost of more deploy gas.
contract AccountFactory {
    /// @dev EntryPoint baked into every account this factory deploys (immutable, in the address math).
    address public immutable entryPoint;

    event AccountCreated(address indexed account, bytes32 pubKeyX, bytes32 pubKeyY, uint256 salt);

    constructor(address _entryPoint) {
        entryPoint = _entryPoint;
    }

    /// @notice Deploys (or returns) the PasskeyAccount for a given P-256 public key.
    /// @param x    P-256 public key X coordinate
    /// @param y    P-256 public key Y coordinate
    /// @param salt Account index for this key (default 0). Uniqueness already comes from (x, y);
    ///             salt lets the same passkey own several accounts.
    /// @return The deployed (or pre-existing) account.
    function createAccount(bytes32 x, bytes32 y, uint256 salt) external returns (PasskeyAccount) {
        address predicted = getAddress(x, y, salt);
        if (predicted.code.length > 0) {
            return PasskeyAccount(payable(predicted)); // idempotent: already deployed
        }
        PasskeyAccount account = new PasskeyAccount{salt: bytes32(salt)}(entryPoint, x, y);
        emit AccountCreated(address(account), x, y, salt);
        return account;
    }

    /// @notice Computes the deterministic (counterfactual) address of a PasskeyAccount.
    /// @dev Same init code (creation bytecode + constructor args) and salt as `createAccount`, so the
    ///      returned address is EXACTLY where the account will (or does) live. The frontend reads this
    ///      to obtain `sender` before the account exists — no off-chain CREATE2 duplication.
    function getAddress(bytes32 x, bytes32 y, uint256 salt) public view returns (address) {
        bytes memory initCode = abi.encodePacked(type(PasskeyAccount).creationCode, abi.encode(entryPoint, x, y));
        return Create2.computeAddress(bytes32(salt), keccak256(initCode));
    }
}
