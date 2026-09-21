// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TipSplitter} from "../../src/TipSplitter.sol";

/// @dev Deliberately unrestricted token used only to exercise untrusted external-call behavior.
contract AdversarialToken {
    enum Mode {
        Normal,
        ReturnFalse,
        RevertCall,
        ShortTransfer,
        NoReturn,
        DecreasePool
    }

    mapping(address => uint256) public balanceOf;
    Mode public incomingMode;
    Mode public outgoingMode;
    address public callbackTarget;
    bytes public callbackData;
    bool public callbackOnIncoming;
    bool public bubbleFailure;
    bool public callbackSucceeded;
    bytes public callbackResult;
    uint256 public callbackCount;
    uint256 public observedClaimed;
    uint256 public observedTotalClaimed;
    uint256 public observedClaimable;

    error TokenRejected();

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function setModes(Mode incoming, Mode outgoing) external {
        incomingMode = incoming;
        outgoingMode = outgoing;
    }

    function setCallback(address target, bytes calldata data, bool incoming, bool bubble) external {
        callbackTarget = target;
        callbackData = data;
        callbackOnIncoming = incoming;
        bubbleFailure = bubble;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (callbackOnIncoming) _callback();
        return _move(from, to, amount, incomingMode);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        observedClaimed = TipSplitter(msg.sender).claimed(to);
        observedTotalClaimed = TipSplitter(msg.sender).totalClaimed();
        observedClaimable = TipSplitter(msg.sender).claimable(to);
        if (!callbackOnIncoming) _callback();
        return _move(msg.sender, to, amount, outgoingMode);
    }

    function _move(address from, address to, uint256 amount, Mode mode) private returns (bool) {
        if (mode == Mode.ReturnFalse) return false;
        if (mode == Mode.RevertCall) revert TokenRejected();
        if (mode == Mode.NoReturn) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }
        if (mode == Mode.DecreasePool) {
            balanceOf[to] -= 1;
            return true;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += mode == Mode.ShortTransfer ? amount - 1 : amount;
        return true;
    }

    function _callback() private {
        if (callbackTarget == address(0)) return;
        ++callbackCount;
        (callbackSucceeded, callbackResult) = callbackTarget.call(callbackData);
        if (bubbleFailure && !callbackSucceeded) {
            bytes memory result = callbackResult;
            assembly ("memory-safe") {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
