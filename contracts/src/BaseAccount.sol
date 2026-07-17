// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccount, PackedUserOperation} from "./interfaces/IAccount.sol";
import {IEntryPoint} from "./interfaces/IEntryPoint.sol";

/// @title BaseAccount
/// @notice Abstract ERC-4337 smart-account base — factors out everything common to all
///         signature schemes (validation flow, prefund, execution, deposit) and leaves the
///         signature check itself as a single overridable hook: `_validateSignature`.
/// @dev Template Method pattern. Concrete accounts (SmartAccount V1, SecretQuestionAccount V2,
///      PasskeyAccount V3) only implement `_validateSignature` (+ `_authorizedAdmin`).
///
///      Lifecycle of a UserOp as seen by an account:
///        1. validateUserOp()  ← EntryPoint asks "is this signature valid?"
///        2. execute()         ← EntryPoint asks "perform the requested action"
abstract contract BaseAccount is IAccount {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev ERC-4337 signature-validation return values.
    ///      0 = success. 1 = signature failure. NEVER revert on a bad signature: RETURN these.
    uint256 internal constant SIG_VALIDATION_SUCCESS = 0;
    uint256 internal constant SIG_VALIDATION_FAILED = 1;

    /*//////////////////////////////////////////////////////////////
                                  STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev EntryPoint this account trusts. Immutable: baked into the bytecode (no SLOAD).
    address private immutable i_entryPoint;

    /*//////////////////////////////////////////////////////////////
                              EVENTS & ERRORS
    //////////////////////////////////////////////////////////////*/

    event Executed(address indexed dest, uint256 value, bytes func);

    error BaseAccount__NotFromEntryPoint();
    error BaseAccount__NotFromEntryPointOrOwner();
    error BaseAccount__ExecuteFailed(bytes result);
    error BaseAccount__WrongArrayLengths();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Restricted to the EntryPoint (validateUserOp: nobody else may trigger a validation).
    modifier requireFromEntryPoint() {
        if (msg.sender != i_entryPoint) revert BaseAccount__NotFromEntryPoint();
        _;
    }

    /// @dev EntryPoint OR the scheme's admin (execute: the EntryPoint runs the normal flow, but
    ///      the admin may also drive its account directly — handy for administration).
    modifier requireFromEntryPointOrOwner() {
        if (msg.sender != i_entryPoint && msg.sender != _authorizedAdmin()) {
            revert BaseAccount__NotFromEntryPointOrOwner();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _entryPoint) {
        i_entryPoint = _entryPoint;
    }

    /// @notice Allows the contract to receive ETH (prefund + excess gas refunds).
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                                VALIDATION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccount
    /// @dev Template: delegate the scheme-specific check to `_validateSignature`, then advance the
    ///      prefund. ABSOLUTE RULE: never revert on a bad signature — return 1.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        requireFromEntryPoint
        returns (uint256 validationData)
    {
        validationData = _validateSignature(userOp, userOpHash);
        _payPrefund(missingAccountFunds);
    }

    /// @notice Scheme-specific signature check — the single overridable hook.
    /// @dev MUST return SIG_VALIDATION_SUCCESS (0) or SIG_VALIDATION_FAILED (1); never revert on a
    ///      malformed/incorrect signature.
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        virtual
        returns (uint256);

    /// @notice Address allowed to drive execute()/executeBatch() directly (besides the EntryPoint).
    /// @dev Each scheme decides its "admin" (the owner in V1, the derived signer in V2).
    function _authorizedAdmin() internal view virtual returns (address);

    /// @dev Transfers the prefund to the EntryPoint if needed (0 when a Paymaster pays). We ignore
    ///      the call's success: the EntryPoint enforces reception itself.
    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(i_entryPoint).call{value: missingAccountFunds}("");
            (success); // intentionally ignored (see NatSpec)
        }
    }

    /*//////////////////////////////////////////////////////////////
                                EXECUTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes an arbitrary action on behalf of the account (step 2 of the lifecycle).
    function execute(address dest, uint256 value, bytes calldata func) external requireFromEntryPointOrOwner {
        _call(dest, value, func);
    }

    /// @notice Executes several actions in a single UserOp. The 3 arrays must have equal length.
    function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata func)
        external
        requireFromEntryPointOrOwner
    {
        if (dest.length != func.length || dest.length != value.length) {
            revert BaseAccount__WrongArrayLengths();
        }
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], value[i], func[i]);
        }
    }

    /// @dev Shared low-level call: executes and bubbles up the revert reason on failure.
    function _call(address dest, uint256 value, bytes calldata func) internal {
        (bool success, bytes memory result) = dest.call{value: value}(func);
        if (!success) {
            revert BaseAccount__ExecuteFailed(result);
        }
        emit Executed(dest, value, func);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT & GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Funds THIS account's deposit on the EntryPoint (the NO-Paymaster case).
    function addDeposit() external payable {
        IEntryPoint(i_entryPoint).depositTo{value: msg.value}(address(this));
    }

    /// @notice Balance deposited by this account on the EntryPoint.
    function getDeposit() external view returns (uint256) {
        return IEntryPoint(i_entryPoint).balanceOf(address(this));
    }

    /// @notice Address of the associated EntryPoint.
    function entryPoint() external view returns (address) {
        return i_entryPoint;
    }
}
