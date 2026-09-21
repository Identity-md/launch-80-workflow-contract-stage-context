// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TipSplitter} from "../src/TipSplitter.sol";
import {AdversarialToken} from "./mocks/AdversarialToken.sol";

contract TipSplitterAdversarialTest is Test {
    AdversarialToken private token;
    TipSplitter private splitter;
    address private alice = address(0xA11CE);

    function setUp() public {
        token = new AdversarialToken();
        splitter = new TipSplitter(address(token));
        token.mint(address(this), 1000);
    }

    function _single(address member) private pure returns (address[] memory list) {
        list = new address[](1);
        list[0] = member;
    }

    function _attack(uint256 index) private view returns (bytes memory) {
        if (index == 0) return abi.encodeCall(TipSplitter.claim, ());
        if (index == 1) return abi.encodeCall(TipSplitter.deposit, (1));
        return abi.encodeCall(TipSplitter.registerMembers, (_single(address(token)), 1));
    }

    function _assertBlocked(uint256 count) private view {
        assertFalse(token.callbackSucceeded());
        assertEq(token.callbackResult(), abi.encodeWithSelector(TipSplitter.Reentrancy.selector));
        assertEq(token.callbackCount(), count);
    }

    function testAllMutatingEntrypointsRejectReentrancyDuringFirstDeposit() public {
        for (uint256 i; i < 3; ++i) {
            TipSplitter fresh = new TipSplitter(address(token));
            token.setCallback(address(fresh), _attack(i), true, false);
            fresh.registerMembers(_single(address(token)), 10);
            _assertBlocked(i + 1);
            assertEq(fresh.memberCount(), 1);
            assertEq(fresh.totalDeposited(), 10);
            assertEq(fresh.totalClaimed(), 0);
            assertEq(token.balanceOf(address(fresh)), 10);
        }
    }

    function testAllMutatingEntrypointsRejectReentrancyDuringLaterDeposits() public {
        splitter.registerMembers(_single(address(token)), 10);
        for (uint256 i; i < 3; ++i) {
            token.setCallback(address(splitter), _attack(i), true, false);
            splitter.deposit(10);
            _assertBlocked(i + 1);
        }
        assertEq(splitter.totalDeposited(), 40);
        assertEq(splitter.totalClaimed(), 0);
        assertEq(splitter.claimable(address(token)), 40);
        assertEq(token.balanceOf(address(splitter)), 40);
    }

    function testPayoutReentrancyIsBlockedAndEffectsPrecedeInteraction() public {
        splitter.registerMembers(_single(address(token)), 10);
        for (uint256 i; i < 3; ++i) {
            token.setCallback(address(splitter), _attack(i), false, false);
            vm.prank(address(token));
            assertEq(splitter.claim(), 10);
            _assertBlocked(i + 1);
            assertEq(token.observedClaimed(), (i + 1) * 10);
            assertEq(token.observedTotalClaimed(), (i + 1) * 10);
            assertEq(token.observedClaimable(), 0);
            if (i < 2) splitter.deposit(10);
        }
        assertEq(token.balanceOf(address(token)), 30);
        assertEq(splitter.totalClaimed(), 30);
        assertEq(token.balanceOf(address(splitter)), 0);
    }

    function testPropagatedReentrancyRollsBackRegistrationAndGuardCanBeRetried() public {
        token.setCallback(address(splitter), _attack(0), true, true);
        vm.expectRevert(TipSplitter.Reentrancy.selector);
        splitter.registerMembers(_single(alice), 10);
        assertEq(splitter.memberCount(), 0);
        assertFalse(splitter.isMember(alice));
        assertEq(splitter.totalDeposited(), 0);
        assertEq(token.balanceOf(address(splitter)), 0);
        token.setCallback(address(0), "", true, false);
        splitter.registerMembers(_single(alice), 10);
    }

    function testPropagatedPayoutReentrancyPreservesClaimRights() public {
        splitter.registerMembers(_single(address(token)), 10);
        token.setCallback(address(splitter), _attack(0), false, true);
        vm.prank(address(token));
        vm.expectRevert(TipSplitter.Reentrancy.selector);
        splitter.claim();
        assertEq(splitter.totalClaimed(), 0);
        assertEq(splitter.claimed(address(token)), 0);
        assertEq(splitter.claimable(address(token)), 10);
        token.setCallback(address(0), "", false, false);
        vm.prank(address(token));
        assertEq(splitter.claim(), 10);
    }

    function testFalseIncomingTransferRollsBackMembershipAndAccounting() public {
        token.setModes(AdversarialToken.Mode.ReturnFalse, AdversarialToken.Mode.Normal);
        vm.expectRevert(TipSplitter.TransferFailed.selector);
        splitter.registerMembers(_single(alice), 10);
        assertEq(splitter.memberCount(), 0);
        assertFalse(splitter.isMember(alice));
        assertEq(splitter.totalDeposited(), 0);
        token.setModes(AdversarialToken.Mode.Normal, AdversarialToken.Mode.Normal);
        splitter.registerMembers(_single(alice), 10);
        token.setModes(AdversarialToken.Mode.ReturnFalse, AdversarialToken.Mode.Normal);
        vm.expectRevert(TipSplitter.TransferFailed.selector);
        splitter.deposit(5);
        assertEq(splitter.totalDeposited(), 10);
        assertEq(token.balanceOf(address(splitter)), 10);
    }

    function testRevertingIncomingTransferPreservesPool() public {
        splitter.registerMembers(_single(alice), 10);
        token.setModes(AdversarialToken.Mode.RevertCall, AdversarialToken.Mode.Normal);
        vm.expectRevert(AdversarialToken.TokenRejected.selector);
        splitter.deposit(5);
        assertEq(splitter.totalDeposited(), 10);
        assertEq(token.balanceOf(address(splitter)), 10);
        assertEq(token.balanceOf(address(this)), 990);
    }

    function testUnderfundedAndDecreasingIncomingTransfersAreRejected() public {
        token.setModes(AdversarialToken.Mode.ShortTransfer, AdversarialToken.Mode.Normal);
        vm.expectRevert(TipSplitter.UnexpectedTokenAmount.selector);
        splitter.registerMembers(_single(alice), 10);
        assertEq(splitter.memberCount(), 0);
        assertEq(token.balanceOf(address(this)), 1000);
        assertEq(token.balanceOf(address(splitter)), 0);
        token.setModes(AdversarialToken.Mode.Normal, AdversarialToken.Mode.Normal);
        splitter.registerMembers(_single(alice), 10);
        token.setModes(AdversarialToken.Mode.DecreasePool, AdversarialToken.Mode.Normal);
        vm.expectRevert(TipSplitter.UnexpectedTokenAmount.selector);
        splitter.deposit(5);
        assertEq(splitter.totalDeposited(), 10);
        assertEq(token.balanceOf(address(splitter)), 10);
    }

    function testFalseAndRevertingPayoutsPreserveClaimsAndCanBeRetried() public {
        splitter.registerMembers(_single(alice), 10);
        token.setModes(AdversarialToken.Mode.Normal, AdversarialToken.Mode.ReturnFalse);
        vm.prank(alice);
        vm.expectRevert(TipSplitter.TransferFailed.selector);
        splitter.claim();
        assertEq(splitter.claimed(alice), 0);
        assertEq(splitter.totalClaimed(), 0);
        assertEq(splitter.claimable(alice), 10);
        token.setModes(AdversarialToken.Mode.Normal, AdversarialToken.Mode.RevertCall);
        vm.prank(alice);
        vm.expectRevert(AdversarialToken.TokenRejected.selector);
        splitter.claim();
        assertEq(splitter.claimed(alice), 0);
        assertEq(token.balanceOf(address(splitter)), 10);
        token.setModes(AdversarialToken.Mode.Normal, AdversarialToken.Mode.Normal);
        vm.prank(alice);
        assertEq(splitter.claim(), 10);
        assertEq(token.balanceOf(alice), 10);
    }

    function testNonstandardMissingReturnDataIsRejectedWithoutLosingFunds() public {
        token.setModes(AdversarialToken.Mode.NoReturn, AdversarialToken.Mode.Normal);
        vm.expectRevert();
        splitter.registerMembers(_single(alice), 10);
        assertEq(splitter.memberCount(), 0);
        token.setModes(AdversarialToken.Mode.Normal, AdversarialToken.Mode.Normal);
        splitter.registerMembers(_single(alice), 10);
        token.setModes(AdversarialToken.Mode.Normal, AdversarialToken.Mode.NoReturn);
        vm.prank(alice);
        vm.expectRevert();
        splitter.claim();
        assertEq(splitter.claimable(alice), 10);
        assertEq(splitter.totalClaimed(), 0);
    }
}
