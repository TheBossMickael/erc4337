// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccount, PackedUserOperation} from "./interfaces/IAccount.sol";
import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title SmartAccount
/// @notice ERC-4337 smart wallet — replaces a classic EOA.
///         Each user deploys their own instance of this contract.
/// @dev V1: standard ECDSA validation (single owner), gas sponsored by an external Paymaster.
///      Implements IAccount directly, without inheriting from BaseAccount.
///
///      Lifecycle of a UserOp as seen by this contract:
///        1. validateUserOp()  ← the EntryPoint asks "is this signature valid?"
///        2. execute()         ← the EntryPoint asks "perform the requested action"
///      The two calls are SEPARATE and both come from the EntryPoint.
contract SmartAccount is IAccount {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Return values of signature validation (ERC-4337 packing).
    ///      0 = success. 1 (= bit 0 set, aggregator address = 0x...01) = signature failure.
    ///      NEVER revert on a bad signature: we RETURN these values.
    uint256 internal constant SIG_VALIDATION_SUCCESS = 0;
    uint256 internal constant SIG_VALIDATION_FAILED = 1;

    /*//////////////////////////////////////////////////////////////
                                  STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Address of the ERC-4337 v0.8 EntryPoint on Sepolia.
    ///      Immutable: set at deployment, baked into the bytecode (no costly SLOAD).
    address private immutable i_entryPoint;

    /// @dev Account owner: the only address allowed to sign valid UserOps.
    address private s_owner;

    /*//////////////////////////////////////////////////////////////
                              EVENTS & ERRORS
    //////////////////////////////////////////////////////////////*/

    event SmartAccountInitialized(address indexed entryPoint, address indexed owner);
    event Executed(address indexed dest, uint256 value, bytes func);

    error SmartAccount__NotFromEntryPoint();
    error SmartAccount__NotFromEntryPointOrOwner();
    error SmartAccount__ExecuteFailed(bytes result);
    error SmartAccount__WrongArrayLengths();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Restricted to the EntryPoint. Used by validateUserOp: nobody else
    ///      must be able to trigger a validation.
    modifier requireFromEntryPoint() {
        if (msg.sender != i_entryPoint) revert SmartAccount__NotFromEntryPoint();
        _;
    }

    /// @dev EntryPoint OR owner. Used by execute: the EntryPoint runs the normal
    ///      ERC-4337 flow, but we also allow the owner to drive its account directly
    ///      (classic EOA transaction), handy for administration.
    modifier requireFromEntryPointOrOwner() {
        if (msg.sender != i_entryPoint && msg.sender != s_owner) {
            revert SmartAccount__NotFromEntryPointOrOwner();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the SmartAccount with its EntryPoint and its owner.
    /// @param _entryPoint EntryPoint address (0x4337...108 on Sepolia)
    /// @param _owner      Owner's EOA address — signs UserOps off-chain
    constructor(address _entryPoint, address _owner) {
        i_entryPoint = _entryPoint;
        s_owner = _owner;
        emit SmartAccountInitialized(_entryPoint, _owner);
    }

    /// @notice Allows the contract to receive ETH.
    /// @dev Needed for the prefund (sending ETH to the EntryPoint) and to receive
    ///      excess gas refunds.
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                                VALIDATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates a UserOperation before its execution by the EntryPoint.
    /// @dev Called exclusively by the EntryPoint during the verification loop.
    ///      ABSOLUTE RULE: never revert on a bad signature — return 1.
    ///      Revert only on a fatal error (wrong caller, prefund impossible).
    /// @param userOp              The UserOperation to validate
    /// @param userOpHash          Hash of the UserOp computed by the EntryPoint
    /// @param missingAccountFunds ETH missing on the EntryPoint deposit (0 if a Paymaster is present)
    /// @return validationData     0 = valid signature, 1 = invalid signature
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        requireFromEntryPoint
        returns (uint256 validationData)
    {
        // 1. Check the signature (never reverts here)
        validationData = _validateSignature(userOp, userOpHash);
        // 2. Advance the prefund if needed (no-op if a Paymaster pays => 0)
        _payPrefund(missingAccountFunds);
    }

    /// @notice Checks that the signature comes from the owner.
    /// @dev Convention: the client signs with "personal_sign" (EIP-191 prefix), so we
    ///      rebuild toEthSignedMessageHash(userOpHash) before ecrecover.
    ///      We use OpenZeppelin's ECDSA.tryRecover:
    ///        - protects against malleability (rejects high "s" values)
    ///        - DOES NOT REVERT on a malformed signature (returns a RecoverError)
    ///          => perfect to honor the "never revert on a bad signature" rule.
    /// @param userOp     The UserOperation (we read userOp.signature)
    /// @param userOpHash Hash provided by the EntryPoint
    /// @return 0 if the signature is the owner's, 1 otherwise
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256)
    {
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(ethSignedHash, userOp.signature);
        if (err != ECDSA.RecoverError.NoError || recovered != s_owner) {
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }

    /// @notice Transfers the prefund to the EntryPoint if the account deposit is insufficient.
    /// @dev missingAccountFunds = maxCost - the account's current deposit on the EntryPoint.
    ///      If a Paymaster is present, this parameter is 0 and the function does nothing.
    ///      We ignore the call's success: the EntryPoint verifies reception itself and
    ///      reverts if the account did not ultimately pay enough.
    /// @param missingAccountFunds ETH missing to send to the EntryPoint (in wei)
    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(i_entryPoint).call{value: missingAccountFunds}("");
            (success); // intentionally ignored (see NatSpec)
        }
    }

    /*//////////////////////////////////////////////////////////////
                                EXECUTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes an arbitrary action on behalf of the account.
    /// @dev This is step 2 of the lifecycle: the EntryPoint calls here via the UserOp callData.
    ///      A UserOp's callData typically encodes a call to THIS function.
    /// @param dest  Target address of the call
    /// @param value Amount of ETH to send (wei)
    /// @param func  Calldata of the call (empty for a plain ETH transfer)
    function execute(address dest, uint256 value, bytes calldata func) external requireFromEntryPointOrOwner {
        _call(dest, value, func);
    }

    /// @notice Executes several actions in a single UserOp (e.g. approve + swap).
    /// @dev The 3 arrays must have the same length.
    /// @param dest  Target addresses
    /// @param value ETH amounts (wei) for each call
    /// @param func  Calldata of each call
    function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata func)
        external
        requireFromEntryPointOrOwner
    {
        if (dest.length != func.length || dest.length != value.length) {
            revert SmartAccount__WrongArrayLengths();
        }
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], value[i], func[i]);
        }
    }

    /// @dev Shared low-level call: executes and bubbles up the revert reason on failure.
    function _call(address dest, uint256 value, bytes calldata func) internal {
        (bool success, bytes memory result) = dest.call{value: value}(func);
        if (!success) {
            revert SmartAccount__ExecuteFailed(result);
        }
        emit Executed(dest, value, func);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT & GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Funds THIS account's deposit on the EntryPoint (the NO-Paymaster case).
    /// @dev Sends msg.value to the EntryPoint, credited to this account. Used to cover the
    ///      gas of future UserOps when not going through a Paymaster.
    function addDeposit() external payable {
        IEntryPoint(i_entryPoint).depositTo{value: msg.value}(address(this));
    }

    /// @notice Balance deposited by this account on the EntryPoint.
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
