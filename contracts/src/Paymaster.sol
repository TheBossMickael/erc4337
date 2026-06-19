// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPaymaster, PackedUserOperation} from "./interfaces/IPaymaster.sol";
import {IEntryPoint} from "./interfaces/IEntryPoint.sol";

/// @title Paymaster
/// @notice Contract that pays the gas on behalf of the user ("sponsoring").
/// @dev V1: UNCONDITIONAL sponsoring — agrees to pay for any UserOp.
///      Real security: DO NOT do this in production (anyone can drain the deposit).
///      This is deliberate and pedagogical. A real version would filter (whitelist, quota,
///      ERC-20 payment, off-chain sponsor signature, etc.).
///
///      IMPORTANT: a Paymaster is NOT an EOA. It does not pay by sending txs.
///      It holds an accounting DEPOSIT on the EntryPoint (funded via depositTo) from
///      which the EntryPoint draws to reimburse the bundler.
contract Paymaster is IPaymaster {
    /*//////////////////////////////////////////////////////////////
                                  STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Associated EntryPoint (immutable, baked into the bytecode).
    address private immutable i_entryPoint;

    /// @dev Owner: the only one allowed to withdraw the deposit.
    address private s_owner;

    /*//////////////////////////////////////////////////////////////
                              EVENTS & ERRORS
    //////////////////////////////////////////////////////////////*/

    event PaymasterDeposited(uint256 amount);
    event PaymasterWithdrawn(address indexed to, uint256 amount);

    error Paymaster__NotFromEntryPoint();
    error Paymaster__NotOwner();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier requireFromEntryPoint() {
        if (msg.sender != i_entryPoint) revert Paymaster__NotFromEntryPoint();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != s_owner) revert Paymaster__NotOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _entryPoint, address _owner) {
        i_entryPoint = _entryPoint;
        s_owner = _owner;
    }

    /*//////////////////////////////////////////////////////////////
                            PAYMASTER LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPaymaster
    /// @dev V1: accepts everything. We return:
    ///        - context = "" (empty) => the EntryPoint WILL NOT call postOp (nothing to reconcile)
    ///        - validationData = 0    => accepted, valid indefinitely (no time window)
    ///      We still check the caller: a non-negotiable minimal security measure.
    ///      Parameters are intentionally unnamed (unused in V1).
    function validatePaymasterUserOp(PackedUserOperation calldata, bytes32, uint256)
        external
        view
        requireFromEntryPoint
        returns (bytes memory context, uint256 validationData)
    {
        return ("", 0);
    }

    /// @inheritdoc IPaymaster
    /// @dev V1: no-op. It is never called anyway since validatePaymasterUserOp returns an
    ///      empty context. Present to satisfy the IPaymaster interface.
    ///      An advanced version would charge the user here (e.g. in an ERC-20 token) based
    ///      on actualGasCost.
    function postOp(PostOpMode, bytes calldata, uint256, uint256) external view requireFromEntryPoint {}

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Funds the Paymaster's deposit on the EntryPoint.
    /// @dev Anyone can credit the sponsor (send ETH for the benefit of gas).
    function deposit() external payable {
        IEntryPoint(i_entryPoint).depositTo{value: msg.value}(address(this));
        emit PaymasterDeposited(msg.value);
    }

    /// @notice Withdraws part of the deposit to an address (owner only).
    /// @param to     Recipient of the funds
    /// @param amount Amount to withdraw (wei)
    function withdrawTo(address payable to, uint256 amount) external onlyOwner {
        IEntryPoint(i_entryPoint).withdrawTo(to, amount);
        emit PaymasterWithdrawn(to, amount);
    }

    /// @notice Balance deposited by this Paymaster on the EntryPoint.
    function getDeposit() external view returns (uint256) {
        return IEntryPoint(i_entryPoint).balanceOf(address(this));
    }

    /// @notice Owner address.
    function owner() external view returns (address) {
        return s_owner;
    }

    /// @notice Address of the associated EntryPoint.
    function entryPoint() external view returns (address) {
        return i_entryPoint;
    }
}
