// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "./interfaces/IERC20.sol";

/// @notice A single, permanent pool of SPLT tips shared equally by one to ten members.
/// @dev Only deposits through registerMembers/deposit are credited. Direct transfers are not tips.
contract TipSplitter {
    IERC20 public immutable token;
    uint256 public constant MAX_MEMBERS = 10;

    address[] private members;
    mapping(address => bool) public isMember;
    mapping(address => uint256) public claimed;
    uint256 public totalDeposited;
    uint256 public totalClaimed;
    bool private entered;

    error InvalidToken();
    error AlreadyRegistered();
    error NotRegistered();
    error InvalidMemberCount();
    error InvalidMember(address member);
    error DuplicateMember(address member);
    error ZeroAmount();
    error NotMember();
    error NothingToClaim();
    error TransferFailed();
    error UnexpectedTokenAmount();
    error Reentrancy();

    event MembersRegistered(address indexed depositor, address[] members);
    event TipDeposited(address indexed depositor, uint256 amount);
    event ShareClaimed(address indexed member, uint256 amount);

    /// @param token_ The deployed Splitwise token; the manifest must supply $token.
    constructor(address token_) {
        if (token_ == address(0) || token_.code.length == 0) revert InvalidToken();
        token = IERC20(token_);
    }

    modifier nonReentrant() {
        if (entered) revert Reentrancy();
        entered = true;
        _;
        entered = false;
    }

    /// @notice Fix the members forever and make the first positive deposit, atomically.
    /// @dev Permissionless: the first successful caller chooses all members, including or excluding itself.
    /// Approve this contract to spend amount before calling. Amounts are in the token's smallest unit.
    function registerMembers(address[] calldata initialMembers, uint256 amount) external nonReentrant {
        if (members.length != 0) revert AlreadyRegistered();
        uint256 count = initialMembers.length;
        if (count == 0 || count > MAX_MEMBERS) revert InvalidMemberCount();
        for (uint256 i; i < count; ++i) {
            address member = initialMembers[i];
            if (member == address(0) || member == address(this)) revert InvalidMember(member);
            if (isMember[member]) revert DuplicateMember(member);
            isMember[member] = true;
            members.push(member);
        }
        emit MembersRegistered(msg.sender, initialMembers);
        _deposit(amount);
    }

    /// @notice Add a positive tip for the registered members. The depositor need not be a member.
    function deposit(uint256 amount) external nonReentrant {
        if (members.length == 0) revert NotRegistered();
        _deposit(amount);
    }

    /// @notice Pull all of the caller's available share to the caller. No deadlines or third-party claims.
    function claim() external nonReentrant returns (uint256 amount) {
        if (!isMember[msg.sender]) revert NotMember();
        amount = claimable(msg.sender);
        if (amount == 0) revert NothingToClaim();

        claimed[msg.sender] += amount;
        totalClaimed += amount;
        emit ShareClaimed(msg.sender, amount);
        if (!token.transfer(msg.sender, amount)) revert TransferFailed();
    }

    /// @notice Equal lifetime entitlement less prior claims. Remainders carry across deposits.
    function claimable(address member) public view returns (uint256) {
        if (!isMember[member]) return 0;
        return totalDeposited / members.length - claimed[member];
    }

    function memberCount() external view returns (uint256) {
        return members.length;
    }

    function getMembers() external view returns (address[] memory) {
        return members;
    }

    function _deposit(uint256 amount) private {
        if (amount == 0) revert ZeroAmount();
        uint256 beforeBalance = token.balanceOf(address(this));
        totalDeposited += amount;
        emit TipDeposited(msg.sender, amount);
        if (!token.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        uint256 afterBalance = token.balanceOf(address(this));
        if (afterBalance < beforeBalance || afterBalance - beforeBalance != amount) revert UnexpectedTokenAmount();
    }
}
