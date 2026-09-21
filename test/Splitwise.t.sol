// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Splitwise} from "../src/Splitwise.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

contract SplitwiseTest is Test {
    Splitwise private token;
    address private alice = address(0xA11CE);
    address private bob = address(0xB0B);

    function setUp() public {
        token = new Splitwise();
    }

    function testMetadataAndSupply() public view {
        assertEq(token.name(), "Splitwise");
        assertEq(token.symbol(), "SPLT");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(this)), 1e27);
    }

    function testConstructorMintsToActualDeployerWithEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), alice, 1e27);
        vm.prank(alice);
        Splitwise other = new Splitwise();
        assertEq(other.balanceOf(alice), other.totalSupply());
        assertEq(other.balanceOf(address(this)), 0);
    }

    function testTransferEventAndZeroTransfer() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 7);
        assertTrue(token.transfer(alice, 7));
        vm.prank(bob);
        assertTrue(token.transfer(alice, 0));
        assertEq(token.balanceOf(alice), 7);
        assertEq(token.balanceOf(address(this)), 1e27 - 7);
    }

    function testSelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), 123));
        assertEq(token.balanceOf(address(this)), 1e27);
    }

    function testCannotTransferMoreThanBalanceOrToZero() public {
        vm.expectRevert(Splitwise.InsufficientBalance.selector);
        token.transfer(alice, 1e27 + 1);
        vm.prank(alice);
        vm.expectRevert(Splitwise.InsufficientBalance.selector);
        token.transfer(bob, 1);
        vm.expectRevert(Splitwise.InvalidRecipient.selector);
        token.transfer(address(0), 1);
        vm.expectRevert(Splitwise.InvalidRecipient.selector);
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), 1e27);
    }

    function testApprovalReplacementRevocationAndInvalidSpender() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), alice, 50);
        assertTrue(token.approve(alice, 50));
        assertTrue(token.approve(alice, 20));
        assertEq(token.allowance(address(this), alice), 20);
        assertTrue(token.approve(alice, 0));
        assertEq(token.allowance(address(this), alice), 0);
        vm.expectRevert(Splitwise.InvalidSpender.selector);
        token.approve(address(0), 1);
    }

    function testTransferFromConsumesFiniteAllowanceAndEmits() public {
        token.approve(alice, 100);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), alice, 60);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), bob, 40);
        vm.prank(alice);
        assertTrue(token.transferFrom(address(this), bob, 40));
        assertEq(token.allowance(address(this), alice), 60);
        assertEq(token.balanceOf(bob), 40);
        vm.prank(alice);
        token.transferFrom(address(this), bob, 60);
        assertEq(token.allowance(address(this), alice), 0);
    }

    function testInfiniteApprovalIsNotConsumed() public {
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(address(this), bob, 1e27);
        assertEq(token.allowance(address(this), alice), type(uint256).max);
        assertEq(token.balanceOf(bob), 1e27);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testTransferFromFailuresAreAtomic() public {
        token.approve(alice, 100);
        vm.prank(bob);
        vm.expectRevert(Splitwise.InsufficientAllowance.selector);
        token.transferFrom(address(this), bob, 1);
        vm.prank(alice);
        vm.expectRevert(Splitwise.InsufficientAllowance.selector);
        token.transferFrom(address(this), bob, 101);
        vm.prank(alice);
        vm.expectRevert(Splitwise.InvalidRecipient.selector);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), alice), 100);
        token.transfer(bob, 1e27);
        vm.prank(alice);
        vm.expectRevert(Splitwise.InsufficientBalance.selector);
        token.transferFrom(address(this), bob, 100);
        assertEq(token.allowance(address(this), alice), 100);
        assertEq(token.balanceOf(bob), 1e27);
    }

    function testUnknownMintAdminAndUpgradeSelectorsRevert() public {
        bytes[5] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", alice, 1),
            abi.encodeWithSignature("burn(uint256)", 1),
            abi.encodeWithSignature("transferOwnership(address)", alice),
            abi.encodeWithSignature("upgradeTo(address)", alice),
            abi.encodeWithSignature("initialize(address)", alice)
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool success,) = address(token).call(calls[i]);
            assertFalse(success);
        }
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(this)), 1e27);
    }

    function testRejectsNativeCurrency() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1}("");
        assertFalse(success);
    }

    function testFuzzTransfersConserveSupply(uint256 amount, uint256 returned) public {
        amount = bound(amount, 0, 1e27);
        returned = bound(returned, 0, amount);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.transfer(address(this), returned);
        assertEq(token.balanceOf(alice), amount - returned);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(alice), token.totalSupply());
    }
}
