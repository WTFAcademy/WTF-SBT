// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../contracts/WTFSBT1155.sol";

contract WTFSBT1155Test is Test {
    WTFSBT1155 public sbt;

    address internal alice;
    address internal bob;
    address constant MINTER_ADDRESS = 0x25df6DA2f4e5C178DdFF45038378C0b08E0Bce54;
    address owner = address(1234);

    function setUp() public {
        vm.startPrank(owner);
        sbt = new WTFSBT1155("Test SBT", "TestSBT", "https://api.wtf.academy/token", msg.sender);
        sbt.createSoul("test01", "test 01", 0, 0, 0);
        sbt.createSoul("test02", "test 02", 10, block.timestamp, block.timestamp+100);
        sbt.addMinter(MINTER_ADDRESS);
        alice = address(1);
        vm.label(alice, "Alice");
        bob = address(2);
        vm.label(bob, "Bob");
        vm.stopPrank();
    }

    function testCreated() public {
        assertEq(sbt.isCreated(0), true, "sbt 01 should exist");
        assertEq(sbt.isCreated(1), true, "sbt 02 should exist");
        assertEq(sbt.isCreated(2), false, "sbt 03 should not exist");
    }

    function testNotMinter() public {
        vm.expectRevert();
        sbt.mint(alice, 0);
    }

    function testMint() public {
        vm.prank(MINTER_ADDRESS);
        sbt.mint(alice, 0);
        assertEq(sbt.balanceOf(alice, 0), 1);
    }

    function testSoulNotCreated() public {
        vm.expectRevert();
        vm.prank(MINTER_ADDRESS);
        sbt.mint(alice, 3);
    }

    function testNonTransferrable() public {
        vm.prank(MINTER_ADDRESS);
        sbt.mint(alice, 0);
        vm.expectRevert();
        vm.prank(alice);
        sbt.safeTransferFrom(alice, bob, 0, 1, "");
    }

    function testRecover() public {
        // only contract owner can transfer under the permision of the holder
        vm.prank(MINTER_ADDRESS);
        sbt.mint(alice, 0);
        vm.prank(alice);
        sbt.setApprovalForAll(owner, true);
        vm.prank(owner);
        sbt.recover(alice, bob);
    }
}
