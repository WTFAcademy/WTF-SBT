// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../contracts/WTFSBT1155.sol";

contract WTFSBT1155Test is Test {
    WTFSBT1155 public sbt;

    address internal alice;
    address internal bob;
    address constant MINTER_ADDRESS =
        0x25df6DA2f4e5C178DdFF45038378C0b08E0Bce54;
    address owner = address(1234);

    function setUp() public {
        vm.startPrank(owner);
        sbt = new WTFSBT1155(
            "Test SBT",
            "TestSBT",
            "https://api.wtf.academy/token",
            owner
        );
        sbt.createSoul("test01", "test 01", 0, 0);
        sbt.createSoul(
            "test02",
            "test 02",
            block.timestamp,
            block.timestamp + 100
        );
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
        vm.expectRevert("Only minters can mint.");
        sbt.mint(alice, 0);
    }

    function testMint() public {
        vm.prank(MINTER_ADDRESS);
        sbt.mint(alice, 0);
        assertEq(sbt.balanceOf(alice, 0), 1);
    }

    function testPaidMint() public payable {
        vm.deal(MINTER_ADDRESS, 10);
        vm.prank(MINTER_ADDRESS);
        sbt.mint{value: 10}(bob, 1);
        assertEq(sbt.balanceOf(bob, 1), 1);
        assertEq(owner.balance, 10);
    }

    function testSoulNotCreated() public {
        vm.expectRevert();
        vm.prank(MINTER_ADDRESS);
        sbt.mint(alice, 3);
    }

    function testNonTransferrable() public {
        vm.prank(MINTER_ADDRESS);
        sbt.mint(alice, 0);
        vm.expectRevert("Soulbound: Transfer failed!");
        vm.prank(alice);
        sbt.safeTransferFrom(alice, bob, 0, 1, "");
    }

    function testRecover() public {
        // only contract minter can transfer under the permision of the holder
        vm.prank(MINTER_ADDRESS);
        sbt.mint(alice, 0);
        assertEq(sbt.balanceOf(alice, 0), 1);
        // vm.prank(alice);
        // sbt.setApprovalForAll(owner, true);
        vm.prank(MINTER_ADDRESS);
        sbt.recover(alice, bob);
        assertEq(sbt.balanceOf(bob, 0), 1);
        assertEq(sbt.balanceOf(alice, 0), 0);
    }

    function testOnlyOwnerCanAddMinter() public {
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                alice
            )
        );
        sbt.addMinter(bob);
        vm.stopPrank();
    }

    function testOnlyOwnerCanRemoveMinter() public {
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                alice
            )
        );
        sbt.removeMinter(MINTER_ADDRESS);
        vm.stopPrank();
    }

    function testPauseAndUnpause() public {
        vm.startPrank(owner);
        sbt.pause();
        vm.expectRevert(
            abi.encodeWithSelector(Pausable.EnforcedPause.selector)
        );
        sbt.createSoul("test03", "test 03", block.timestamp, 0);
        sbt.unpause();
        sbt.createSoul("test03", "test 03", block.timestamp, 0);
        assertEq(sbt.getSoulName(2), "test03");
        vm.stopPrank();
    }

    function testOnlyOwnerCanPause() public {
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                alice
            )
        );
        sbt.pause();
        vm.stopPrank();
    }

    function testOnlyOwnerCanUnpause() public {
        vm.startPrank(owner);
        sbt.pause();
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                alice
            )
        );
        sbt.unpause();
        vm.stopPrank();
    }

    function testOnlyOwnerCanSetBaseURI() public {
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                alice
            )
        );
        sbt.setbaseURI("https://api.newexample.com/metadata/");
        vm.stopPrank();
    }

    function testOnlyOwnerCanTransferTreasury() public {
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                alice
            )
        );
        sbt.transferTreasury(address(6));
        assertEq(sbt.treasury(), owner);
        vm.stopPrank();

        vm.prank(owner);
        sbt.transferTreasury(address(6));
        assertEq(sbt.treasury(), address(6));
    }

    function testMintExpiredSoul() public {
        vm.startPrank(owner);
        // Create a soul that is already expired
        vm.warp(block.timestamp + 2 days);
        vm.stopPrank();

        vm.startPrank(MINTER_ADDRESS);
        vm.expectRevert("Mint has ended");
        sbt.mint(alice, 1);
        vm.stopPrank();
    }

    function testMintBeforeStart() public {
        vm.startPrank(owner);
        sbt.createSoul("test03", "test 03", block.timestamp + 1 days, 0);
        vm.stopPrank();

        vm.startPrank(MINTER_ADDRESS);
        vm.expectRevert("Mint has not started");
        sbt.mint(alice, 2);
        vm.stopPrank();
    }

    function testAddAndRemoveMinter() public {
        vm.startPrank(owner);
        sbt.addMinter(alice);
        assertTrue(sbt.isMinter(alice));
        sbt.removeMinter(alice);
        assertFalse(sbt.isMinter(alice));
        vm.stopPrank();
    }

    function testBurnTokens() public {
        vm.startPrank(MINTER_ADDRESS);
        sbt.mint(bob, 1);
        assertEq(sbt.balanceOf(bob, 1), 1);
        vm.stopPrank();

        vm.startPrank(bob);
        sbt.burn(bob, 1, 1);
        assertEq(sbt.balanceOf(bob, 1), 0);
        vm.stopPrank();
    }

    function testBurnBatchTokens() public {
        vm.startPrank(MINTER_ADDRESS);
        sbt.mint(bob, 0);
        sbt.mint(bob, 1);
        assertEq(sbt.balanceOf(bob, 0), 1);
        assertEq(sbt.balanceOf(bob, 1), 1);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](2);
        ids[0] = 0;
        ids[1] = 1;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        vm.startPrank(bob);
        sbt.burnBatch(bob, ids, amounts);
        assertEq(sbt.balanceOf(bob, 0), 0);
        assertEq(sbt.balanceOf(bob, 1), 0);
        vm.stopPrank();
    }
}
