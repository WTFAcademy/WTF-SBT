// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../contracts/WTFSBT1155Minter.sol";

contract WTFSBT1155MinterTest is Test {

    using ECDSA for bytes32;

    WTFSBT1155 public sbt;
    WTFSBT1155Minter public minter;

    address internal alice;
    address internal bob;

    uint256 internal ownerPrivateKey;
    address owner;
    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);

        vm.startPrank(owner);
        sbt = new WTFSBT1155("Test SBT", "TestSBT", "https://api.wtf.academy/token", msg.sender);
        sbt.createSoul("test01", "test 01", 0, 0, 0);
        sbt.createSoul("test02", "test 02", 10, block.timestamp, block.timestamp+100);

        minter = new WTFSBT1155Minter(payable(sbt), owner);
        sbt.addMinter(address(minter));

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
        vm.prank(address(minter));
        sbt.mint(alice, 0);
        assertEq(sbt.balanceOf(alice, 0), 1);
    }

    function testMinterMint() public {
        uint256 soulID_ = 0;
        // ECDSA verify
        bytes32 msgHash = keccak256(abi.encodePacked(alice, soulID_)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, msgHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(alice);
        minter.mint(alice, 0,signature);
        assertEq(sbt.balanceOf(alice, 0), 1);
    }


}