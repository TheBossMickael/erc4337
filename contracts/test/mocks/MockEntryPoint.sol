// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockEntryPoint
/// @notice FAKE EntryPoint for UNIT tests (local EVM).
/// @dev Reproduces only the deposit accounting our contracts need:
///        - depositTo / balanceOf / withdrawTo
///        - receive() to collect the prefund sent by SmartAccount._payPrefund
///      It does NOT simulate the validation/execution loop: in unit tests we call
///      validateUserOp / execute directly with vm.prank(address(this)).
///      To test the real handleOps flow, see Integration.fork.t.sol.
contract MockEntryPoint {
    mapping(address => uint256) public deposits;

    /// @dev Credits an account's deposit (equivalent of the real depositTo).
    function depositTo(address account) external payable {
        deposits[account] += msg.value;
    }

    /// @dev Reads an account's deposit.
    function balanceOf(address account) external view returns (uint256) {
        return deposits[account];
    }

    /// @dev Debits the caller's deposit and sends the funds to it.
    function withdrawTo(address payable to, uint256 amount) external {
        require(deposits[msg.sender] >= amount, "MockEntryPoint: insufficient balance");
        deposits[msg.sender] -= amount;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "MockEntryPoint: withdraw failed");
    }

    /// @dev Collects the prefund (SmartAccount._payPrefund makes an empty call with value).
    ///      We credit the sender's deposit so it can be asserted in the tests.
    receive() external payable {
        deposits[msg.sender] += msg.value;
    }
}
