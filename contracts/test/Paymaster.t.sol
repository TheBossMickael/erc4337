// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Paymaster} from "../src/Paymaster.sol";
import {IPaymaster, PackedUserOperation} from "../src/interfaces/IPaymaster.sol";
import {MockEntryPoint} from "./mocks/MockEntryPoint.sol";

/// @title PaymasterTest — unit tests for Paymaster (local EVM)
contract PaymasterTest is Test {
    Paymaster internal paymaster;
    MockEntryPoint internal entryPoint;

    address internal owner = address(0x0011);
    address internal stranger = address(0xDEAD);

    function setUp() public {
        entryPoint = new MockEntryPoint();
        paymaster = new Paymaster(address(entryPoint), owner);
    }

    /*//////////////////////////////////////////////////////////////
                            PAYMASTER LOGIC
    //////////////////////////////////////////////////////////////*/

    function test_validatePaymasterUserOp_acceptsUnconditionally() public {
        PackedUserOperation memory userOp; // all-zero is enough in V1

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) =
            paymaster.validatePaymasterUserOp(userOp, bytes32(0), 0);

        assertEq(context.length, 0, "empty context => postOp not called");
        assertEq(validationData, 0, "0 => sponsoring accepted");
    }

    function test_validatePaymasterUserOp_notFromEntryPoint_reverts() public {
        PackedUserOperation memory userOp;

        vm.prank(stranger);
        vm.expectRevert(Paymaster.Paymaster__NotFromEntryPoint.selector);
        paymaster.validatePaymasterUserOp(userOp, bytes32(0), 0);
    }

    function test_postOp_notFromEntryPoint_reverts() public {
        vm.prank(stranger);
        vm.expectRevert(Paymaster.Paymaster__NotFromEntryPoint.selector);
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, "", 0, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function test_deposit_increasesDeposit() public {
        vm.deal(address(this), 1 ether);
        paymaster.deposit{value: 0.5 ether}();
        assertEq(paymaster.getDeposit(), 0.5 ether);
    }

    function test_withdrawTo_byOwner() public {
        vm.deal(address(this), 1 ether);
        paymaster.deposit{value: 0.5 ether}();

        address payable recipient = payable(address(0xCAFE));
        vm.prank(owner);
        paymaster.withdrawTo(recipient, 0.2 ether);

        assertEq(recipient.balance, 0.2 ether);
        assertEq(paymaster.getDeposit(), 0.3 ether);
    }

    function test_withdrawTo_notOwner_reverts() public {
        vm.deal(address(this), 1 ether);
        paymaster.deposit{value: 0.5 ether}();

        vm.prank(stranger);
        vm.expectRevert(Paymaster.Paymaster__NotOwner.selector);
        paymaster.withdrawTo(payable(stranger), 0.1 ether);
    }

    function test_getters() public view {
        assertEq(paymaster.owner(), owner);
        assertEq(paymaster.entryPoint(), address(entryPoint));
    }
}
