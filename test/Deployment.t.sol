// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Splitwise} from "../src/Splitwise.sol";
import {TipSplitter} from "../src/TipSplitter.sol";

contract FactoryFixture {
    function deploy() external returns (Splitwise token, TipSplitter splitter) {
        token = new Splitwise{salt: bytes32(uint256(1))}();
        splitter = new TipSplitter{salt: bytes32(uint256(2))}(address(token));
    }
}

contract DeploymentTest is Test {
    function testFactoryDeploymentPreservesSupplyAndConfiguresApplication() public {
        FactoryFixture factory = new FactoryFixture();
        (Splitwise token, TipSplitter splitter) = factory.deploy();
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(factory)), 1e27);
        assertEq(token.balanceOf(address(splitter)), 0);
        assertEq(address(splitter.token()), address(token));
        assertEq(splitter.memberCount(), 0);
        _checkRuntime(address(token));
        _checkRuntime(address(splitter));
    }

    function testConstructorsRejectNativeValue() public {
        vm.deal(address(this), 2);
        bytes memory tokenCode = type(Splitwise).creationCode;
        address deployed;
        assembly ("memory-safe") {
            deployed := create(1, add(tokenCode, 32), mload(tokenCode))
        }
        assertEq(deployed, address(0));
        Splitwise token = new Splitwise();
        bytes memory appCode = abi.encodePacked(type(TipSplitter).creationCode, abi.encode(address(token)));
        assembly ("memory-safe") {
            deployed := create(1, add(appCode, 32), mload(appCode))
        }
        assertEq(deployed, address(0));
    }

    function _checkRuntime(address deployed) private view {
        bytes memory runtime = deployed.code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
            } else {
                assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff, "forbidden runtime opcode");
            }
        }
    }
}
