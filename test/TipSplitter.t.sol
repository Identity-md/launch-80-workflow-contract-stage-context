// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Splitwise} from "../src/Splitwise.sol";
import {TipSplitter} from "../src/TipSplitter.sol";

contract TipSplitterTest is Test {
    Splitwise private token;
    TipSplitter private splitter;
    address private alice = address(0xA11CE);
    address private bob = address(0xB0B);
    address private carol = address(0xCA401);

    function setUp() public {
        token = new Splitwise();
        splitter = new TipSplitter(address(token));
        token.approve(address(splitter), type(uint256).max);
    }

    function _members(uint256 count) private pure returns (address[] memory list) {
        list = new address[](count);
        for (uint256 i; i < count; ++i) {
            list[i] = address(uint160(0x1000 + i));
        }
    }

    function _pair() private view returns (address[] memory list) {
        list = new address[](2);
        list[0] = alice;
        list[1] = bob;
    }

    function testConstructorSetsOnlyTokenAndRejectsInvalidAddresses() public {
        assertEq(address(splitter.token()), address(token));
        assertEq(splitter.memberCount(), 0);
        assertEq(splitter.claimable(alice), 0);
        assertEq(token.balanceOf(address(this)), token.totalSupply());
        vm.expectRevert(TipSplitter.InvalidToken.selector);
        new TipSplitter(address(0));
        vm.expectRevert(TipSplitter.InvalidToken.selector);
        new TipSplitter(alice);
    }

    function testRegistrationAndFirstTipAreAtomicAndEmitEvents() public {
        address[] memory list = _pair();
        vm.expectEmit(true, false, false, true, address(splitter));
        emit TipSplitter.MembersRegistered(address(this), list);
        vm.expectEmit(true, false, false, true, address(splitter));
        emit TipSplitter.TipDeposited(address(this), 100);
        splitter.registerMembers(list, 100);
        assertEq(splitter.getMembers(), list);
        assertEq(splitter.memberCount(), 2);
        assertTrue(splitter.isMember(alice));
        assertTrue(splitter.isMember(bob));
        assertFalse(splitter.isMember(address(this)));
        assertEq(splitter.totalDeposited(), 100);
        assertEq(token.balanceOf(address(splitter)), 100);
        assertEq(splitter.claimable(alice), 50);
    }

    function testOneMemberGetsWholePool() public {
        address[] memory list = _members(1);
        splitter.registerMembers(list, 1e27);
        vm.prank(list[0]);
        assertEq(splitter.claim(), 1e27);
        assertEq(token.balanceOf(list[0]), 1e27);
        assertEq(token.balanceOf(address(splitter)), 0);
    }

    function testTenMembersCanClaimAllSharesInReverseOrder() public {
        address[] memory list = _members(10);
        splitter.registerMembers(list, 1000);
        for (uint256 i = list.length; i > 0; --i) {
            vm.prank(list[i - 1]);
            assertEq(splitter.claim(), 100);
        }
        assertEq(splitter.totalClaimed(), 1000);
        assertEq(token.balanceOf(address(splitter)), 0);
    }

    function testCannotRegisterEmptyOrTooManyMembers() public {
        vm.expectRevert(TipSplitter.InvalidMemberCount.selector);
        splitter.registerMembers(_members(0), 1);
        vm.expectRevert(TipSplitter.InvalidMemberCount.selector);
        splitter.registerMembers(_members(11), 1);
        assertEq(splitter.memberCount(), 0);
    }

    function testInvalidAndDuplicateMembersRollBackWholeList() public {
        address[] memory list = _pair();
        list[1] = address(0);
        vm.expectRevert(abi.encodeWithSelector(TipSplitter.InvalidMember.selector, address(0)));
        splitter.registerMembers(list, 100);
        assertFalse(splitter.isMember(alice));
        list[1] = address(splitter);
        vm.expectRevert(abi.encodeWithSelector(TipSplitter.InvalidMember.selector, address(splitter)));
        splitter.registerMembers(list, 100);
        list[1] = alice;
        vm.expectRevert(abi.encodeWithSelector(TipSplitter.DuplicateMember.selector, alice));
        splitter.registerMembers(list, 100);
        assertEq(splitter.memberCount(), 0);
        assertFalse(splitter.isMember(alice));
        splitter.registerMembers(_pair(), 100);
    }

    function testZeroFirstTipDoesNotReserveMembership() public {
        vm.expectRevert(TipSplitter.ZeroAmount.selector);
        splitter.registerMembers(_pair(), 0);
        assertEq(splitter.memberCount(), 0);
        assertFalse(splitter.isMember(alice));
        assertEq(splitter.totalDeposited(), 0);
        splitter.registerMembers(_members(1), 1);
    }

    function testInsufficientAllowanceDoesNotReserveMembership() public {
        token.approve(address(splitter), 0);
        vm.expectRevert(Splitwise.InsufficientAllowance.selector);
        splitter.registerMembers(_pair(), 1);
        assertEq(splitter.memberCount(), 0);
        assertFalse(splitter.isMember(alice));
        assertEq(splitter.totalDeposited(), 0);
        token.approve(address(splitter), 1);
        splitter.registerMembers(_members(1), 1);
    }

    function testInsufficientBalanceDoesNotReserveMembership() public {
        vm.expectRevert(Splitwise.InsufficientBalance.selector);
        splitter.registerMembers(_pair(), 1e27 + 1);
        assertEq(splitter.memberCount(), 0);
        assertEq(splitter.totalDeposited(), 0);
        assertEq(token.balanceOf(address(splitter)), 0);
    }

    function testFirstSuccessfulCallerWinsRegistrationPermanently() public {
        token.transfer(carol, 1);
        vm.startPrank(carol);
        token.approve(address(splitter), 1);
        splitter.registerMembers(_members(1), 1);
        vm.stopPrank();
        vm.expectRevert(TipSplitter.AlreadyRegistered.selector);
        splitter.registerMembers(_pair(), 100);
        vm.prank(carol);
        vm.expectRevert(TipSplitter.AlreadyRegistered.selector);
        splitter.registerMembers(_pair(), 1);
        assertEq(splitter.getMembers(), _members(1));
    }

    function testDepositBeforeRegistrationAndZeroDepositRevert() public {
        vm.expectRevert(TipSplitter.NotRegistered.selector);
        splitter.deposit(10);
        splitter.registerMembers(_pair(), 10);
        vm.expectRevert(TipSplitter.ZeroAmount.selector);
        splitter.deposit(0);
        assertEq(splitter.totalDeposited(), 10);
    }

    function testAnyoneCanTipAndNoCallerCanSpendAnotherAccount() public {
        splitter.registerMembers(_pair(), 10);
        token.transfer(carol, 7);
        vm.startPrank(carol);
        token.approve(address(splitter), 7);
        vm.expectEmit(true, false, false, true, address(splitter));
        emit TipSplitter.TipDeposited(carol, 7);
        splitter.deposit(7);
        vm.expectRevert(Splitwise.InsufficientAllowance.selector);
        splitter.deposit(1);
        vm.stopPrank();
        assertEq(splitter.totalDeposited(), 17);
        assertEq(token.balanceOf(carol), 0);
        assertEq(splitter.claimable(carol), 0);
        assertEq(splitter.claimable(alice), 8);
    }

    function testMemberCanAlsoDeposit() public {
        splitter.registerMembers(_pair(), 2);
        token.transfer(alice, 4);
        vm.startPrank(alice);
        token.approve(address(splitter), 4);
        splitter.deposit(4);
        assertEq(splitter.claim(), 3);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 3);
        assertEq(splitter.claimable(bob), 3);
    }

    function testUnauthorizedEmptyAndRepeatedClaimsRevert() public {
        vm.prank(alice);
        vm.expectRevert(TipSplitter.NotMember.selector);
        splitter.claim();
        splitter.registerMembers(_pair(), 1);
        vm.expectRevert(TipSplitter.NotMember.selector);
        splitter.claim();
        vm.prank(alice);
        vm.expectRevert(TipSplitter.NothingToClaim.selector);
        splitter.claim();
        splitter.deposit(1);
        vm.prank(alice);
        splitter.claim();
        vm.prank(alice);
        vm.expectRevert(TipSplitter.NothingToClaim.selector);
        splitter.claim();
        assertEq(splitter.claimed(alice), 1);
        assertEq(splitter.totalClaimed(), 1);
    }

    function testClaimEventAndAccounting() public {
        splitter.registerMembers(_pair(), 10);
        vm.expectEmit(true, false, false, true, address(splitter));
        emit TipSplitter.ShareClaimed(alice, 5);
        vm.prank(alice);
        assertEq(splitter.claim(), 5);
        assertEq(splitter.claimable(alice), 0);
        assertEq(splitter.claimable(bob), 5);
        assertEq(splitter.claimed(alice), 5);
        assertEq(splitter.totalClaimed(), 5);
        assertEq(token.balanceOf(alice), 5);
    }

    function testRemaindersCarryAcrossTipsAndClaimsNeverDiluteOtherMembers() public {
        address[] memory list = _members(3);
        splitter.registerMembers(list, 2);
        assertEq(splitter.claimable(list[0]), 0);
        splitter.deposit(2);
        vm.prank(list[0]);
        assertEq(splitter.claim(), 1);
        splitter.deposit(2);
        assertEq(splitter.claimable(list[0]), 1);
        assertEq(splitter.claimable(list[1]), 2);
        assertEq(splitter.claimable(list[2]), 2);
        for (uint256 i; i < 3; ++i) {
            vm.prank(list[i]);
            splitter.claim();
            assertEq(token.balanceOf(list[i]), 2);
        }
        assertEq(token.balanceOf(address(splitter)), 0);
    }

    function testSameBlockAndDistantFutureClaimsHaveNoDeadline() public {
        splitter.registerMembers(_pair(), 10);
        vm.prank(alice);
        splitter.claim();
        vm.warp(block.timestamp + 100 * 365 days);
        vm.roll(block.number + 1_000_000);
        splitter.deposit(10);
        vm.prank(bob);
        assertEq(splitter.claim(), 10);
        vm.prank(alice);
        assertEq(splitter.claim(), 5);
        assertEq(token.balanceOf(alice), token.balanceOf(bob));
    }

    function testDirectTransfersDoNotCreateClaimRightsOrBlockRegistration() public {
        token.transfer(address(splitter), 7);
        splitter.registerMembers(_pair(), 4);
        vm.prank(alice);
        splitter.claim();
        vm.prank(bob);
        splitter.claim();
        assertEq(token.balanceOf(address(splitter)), 7);
        assertEq(splitter.totalDeposited(), 4);
        assertEq(splitter.totalClaimed(), 4);
        assertEq(splitter.claimable(alice), 0);
    }

    function testRejectsNativeCurrencyAndUnknownSelectors() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(splitter).call{value: 1}("");
        assertFalse(success);
        (success,) = address(splitter).call(abi.encodeWithSignature("withdraw(address)", address(this)));
        assertFalse(success);
    }

    function testFuzzClaimOrderAndConservation(uint256 first, uint256 second, uint8 countSeed) public {
        uint256 count = bound(countSeed, 1, 10);
        first = bound(first, 1, 1e24);
        second = bound(second, 1, 1e24);
        address[] memory list = _members(count);
        splitter.registerMembers(list, first);
        if (splitter.claimable(list[0]) != 0) {
            vm.prank(list[0]);
            splitter.claim();
        }
        splitter.deposit(second);
        uint256 share = (first + second) / count;
        for (uint256 i = count; i > 0; --i) {
            if (splitter.claimable(list[i - 1]) != 0) {
                vm.prank(list[i - 1]);
                splitter.claim();
            }
            assertEq(token.balanceOf(list[i - 1]), share);
        }
        assertEq(splitter.totalClaimed(), count * share);
        assertEq(token.balanceOf(address(splitter)), (first + second) % count);
        assertEq(splitter.totalClaimed() + token.balanceOf(address(splitter)), first + second);
    }
}
