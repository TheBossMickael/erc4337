// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Counter — witness contract for the ERC-4337 demo
/// @notice Trivial counter: each call to increment() adds 1.
/// @dev Used ONLY to prove that a UserOperation can CALL A FUNCTION on another contract
///      (and not just transfer ETH).
///      The emitted `caller` will be the SmartAccount's address: it is the account that
///      acts, not the user's EOA — the whole point of account abstraction.
contract Counter {
    uint256 private s_count;

    event Incremented(uint256 newCount, address indexed caller);

    /// @notice Increments the counter by 1.
    function increment() external {
        s_count += 1;
        emit Incremented(s_count, msg.sender);
    }

    /// @notice Current value of the counter.
    function count() external view returns (uint256) {
        return s_count;
    }
}
