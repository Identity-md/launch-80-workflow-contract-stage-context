// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Splitwise} from "../src/Splitwise.sol";
import {TipSplitter} from "../src/TipSplitter.sol";

contract SplitterHandler is Test {
    Splitwise public token;
    TipSplitter public splitter;
    address[] private members;
    uint256 public ghostDeposited;
    uint256 public ghostClaimed;
    uint256 public ghostDonated;

    constructor(Splitwise token_, TipSplitter splitter_, address[] memory members_) {
        token = token_;
        splitter = splitter_;
        members = members_;
        ghostDeposited = splitter.totalDeposited();
        token.approve(address(splitter), type(uint256).max);
    }

    function deposit(uint256 seed) external {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) return;
        uint256 amount = bound(seed, 1, balance);
        splitter.deposit(amount);
        ghostDeposited += amount;
    }

    function claim(uint256 seed) external {
        address member = members[seed % members.length];
        uint256 expected = ghostDeposited / members.length - token.balanceOf(member);
        if (expected == 0) return;
        vm.prank(member);
        assertEq(splitter.claim(), expected);
        ghostClaimed += expected;
    }

    function donateDirectly(uint256 seed) external {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) return;
        uint256 amount = bound(seed, 1, balance);
        token.transfer(address(splitter), amount);
        ghostDonated += amount;
    }
}

contract TipSplitterInvariantTest is StdInvariant, Test {
    Splitwise private token;
    TipSplitter private splitter;
    SplitterHandler private handler;
    address[] private members;

    function setUp() public {
        token = new Splitwise();
        splitter = new TipSplitter(address(token));
        members.push(address(0xA11CE));
        members.push(address(0xB0B));
        members.push(address(0xCA401));
        token.approve(address(splitter), 7);
        splitter.registerMembers(members, 7);
        handler = new SplitterHandler(token, splitter, members);
        token.transfer(address(handler), token.balanceOf(address(this)));
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = SplitterHandler.deposit.selector;
        selectors[1] = SplitterHandler.claim.selector;
        selectors[2] = SplitterHandler.donateDirectly.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariantAccountingConservationAndEqualEntitlements() public view {
        uint256 received = handler.ghostDeposited();
        uint256 paid;
        uint256 pending;
        for (uint256 i; i < members.length; ++i) {
            uint256 balance = token.balanceOf(members[i]);
            uint256 due = splitter.claimable(members[i]);
            assertEq(balance, splitter.claimed(members[i]));
            assertEq(balance + due, received / members.length);
            paid += balance;
            pending += due;
        }
        assertEq(splitter.totalDeposited(), received);
        assertEq(splitter.totalClaimed(), handler.ghostClaimed());
        assertEq(paid, splitter.totalClaimed());
        uint256 held = token.balanceOf(address(splitter));
        assertEq(held + paid, received + handler.ghostDonated());
        assertEq(held, pending + received % members.length + handler.ghostDonated());
        assertEq(held + paid + token.balanceOf(address(handler)), 1e27);
        assertEq(token.totalSupply(), 1e27);
        assertEq(splitter.getMembers(), members);
    }

    function afterInvariant() public {
        for (uint256 i; i < members.length; ++i) {
            if (splitter.claimable(members[i]) != 0) {
                vm.prank(members[i]);
                splitter.claim();
            }
            assertEq(token.balanceOf(members[i]), handler.ghostDeposited() / members.length);
        }
        assertEq(token.balanceOf(address(splitter)), handler.ghostDeposited() % members.length + handler.ghostDonated());
    }
}
