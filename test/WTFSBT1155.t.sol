// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
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
        vm.expectRevert();
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
        vm.expectRevert();
        vm.prank(alice);
        sbt.safeTransferFrom(alice, bob, 0, 1, "");
    }

    /* ============ batchMint ============ */

    event BatchMinted(uint256 count);

    function testBatchMint() public {
        address carol = address(3);
        address[] memory to = new address[](3);
        uint256[] memory soulIds = new uint256[](3);
        to[0] = alice;
        soulIds[0] = 0;
        to[1] = bob;
        soulIds[1] = 1;
        to[2] = carol;
        soulIds[2] = 0;

        vm.expectEmit(false, false, false, true);
        emit BatchMinted(3);
        vm.prank(MINTER_ADDRESS);
        sbt.batchMint(to, soulIds);

        assertEq(sbt.balanceOf(alice, 0), 1, "Alice should hold soul 0");
        assertEq(sbt.balanceOf(bob, 1), 1, "Bob should hold soul 1");
        assertEq(sbt.balanceOf(carol, 0), 1, "Carol should hold soul 0");
        assertEq(sbt.balanceOf(alice, 1), 0, "Alice should not hold soul 1");
        assertEq(sbt.totalSupply(0), 2, "soul 0 supply should be 2");
        assertEq(sbt.totalSupply(1), 1, "soul 1 supply should be 1");
    }

    function testBatchMintLengthMismatch() public {
        address[] memory to = new address[](2);
        uint256[] memory soulIds = new uint256[](1);
        to[0] = alice;
        to[1] = bob;
        soulIds[0] = 0;

        vm.expectRevert("Length mismatch");
        vm.prank(MINTER_ADDRESS);
        sbt.batchMint(to, soulIds);
    }

    function testBatchMintEmptyBatch() public {
        address[] memory to = new address[](0);
        uint256[] memory soulIds = new uint256[](0);

        vm.expectRevert("Empty batch");
        vm.prank(MINTER_ADDRESS);
        sbt.batchMint(to, soulIds);
    }

    function testBatchMintIdempotentRerun() public {
        address carol = address(3);

        // first (partial) run: alice + bob
        address[] memory first = new address[](2);
        uint256[] memory firstIds = new uint256[](2);
        first[0] = alice;
        firstIds[0] = 0;
        first[1] = bob;
        firstIds[1] = 0;
        vm.prank(MINTER_ADDRESS);
        sbt.batchMint(first, firstIds);

        // re-run the full list: alice + bob are skipped, only carol is minted
        address[] memory second = new address[](3);
        uint256[] memory secondIds = new uint256[](3);
        second[0] = alice;
        secondIds[0] = 0;
        second[1] = bob;
        secondIds[1] = 0;
        second[2] = carol;
        secondIds[2] = 0;

        vm.expectEmit(false, false, false, true);
        emit BatchMinted(1);
        vm.prank(MINTER_ADDRESS);
        sbt.batchMint(second, secondIds);

        assertEq(sbt.balanceOf(alice, 0), 1, "Alice should still hold only 1");
        assertEq(sbt.balanceOf(bob, 0), 1, "Bob should still hold only 1");
        assertEq(sbt.balanceOf(carol, 0), 1, "Carol should now hold 1");
        assertEq(sbt.totalSupply(0), 3, "soul 0 supply should be 3");
    }

    function testBatchMintDuplicateInSameBatch() public {
        // the same (recipient, soul) twice in one batch mints only once
        address[] memory to = new address[](2);
        uint256[] memory soulIds = new uint256[](2);
        to[0] = alice;
        soulIds[0] = 0;
        to[1] = alice;
        soulIds[1] = 0;

        vm.expectEmit(false, false, false, true);
        emit BatchMinted(1);
        vm.prank(MINTER_ADDRESS);
        sbt.batchMint(to, soulIds);

        assertEq(sbt.balanceOf(alice, 0), 1, "Alice should hold exactly 1");
    }

    function testBatchMintNotMinter() public {
        address[] memory to = new address[](1);
        uint256[] memory soulIds = new uint256[](1);
        to[0] = alice;
        soulIds[0] = 0;

        vm.expectRevert("Only minters can mint.");
        vm.prank(bob);
        sbt.batchMint(to, soulIds);
    }

    function testBatchMintPaused() public {
        address[] memory to = new address[](1);
        uint256[] memory soulIds = new uint256[](1);
        to[0] = alice;
        soulIds[0] = 0;

        vm.prank(owner);
        sbt.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(MINTER_ADDRESS);
        sbt.batchMint(to, soulIds);

        vm.prank(owner);
        sbt.unpause();
        vm.prank(MINTER_ADDRESS);
        sbt.batchMint(to, soulIds);
        assertEq(sbt.balanceOf(alice, 0), 1, "Alice should hold soul 0");
    }

    function testBatchMintSoulNotCreated() public {
        address[] memory to = new address[](2);
        uint256[] memory soulIds = new uint256[](2);
        to[0] = alice;
        soulIds[0] = 0;
        to[1] = bob;
        soulIds[1] = 3; // never created

        vm.expectRevert("SoulId is not created yet");
        vm.prank(MINTER_ADDRESS);
        sbt.batchMint(to, soulIds);

        // whole batch reverted, nothing was minted
        assertEq(sbt.balanceOf(alice, 0), 0, "Alice should hold nothing");
    }

    function testBatchMintExpiredWindow() public {
        // soul 1 has endDateTimestamp = setUp timestamp + 100
        address[] memory to = new address[](1);
        uint256[] memory soulIds = new uint256[](1);
        to[0] = alice;
        soulIds[0] = 1;

        vm.warp(sbt.getSoulEndDateTimestamp(1) + 1);
        vm.expectRevert("Mint has ended");
        vm.prank(MINTER_ADDRESS);
        sbt.batchMint(to, soulIds);
    }

    function testBatchMintNotStarted() public {
        vm.prank(owner);
        sbt.createSoul("test03", "test 03", block.timestamp + 1000, 0);

        address[] memory to = new address[](1);
        uint256[] memory soulIds = new uint256[](1);
        to[0] = alice;
        soulIds[0] = 2;

        vm.expectRevert("Mint has not started");
        vm.prank(MINTER_ADDRESS);
        sbt.batchMint(to, soulIds);
    }

    function testBatchMintNotPayable() public {
        // batchMint must not accept value: the call reverts if ETH is attached
        address[] memory to = new address[](1);
        uint256[] memory soulIds = new uint256[](1);
        to[0] = alice;
        soulIds[0] = 0;

        vm.deal(MINTER_ADDRESS, 1 ether);
        vm.prank(MINTER_ADDRESS);
        (bool ok, ) = address(sbt).call{value: 1}(
            abi.encodeWithSelector(sbt.batchMint.selector, to, soulIds)
        );
        assertEq(ok, false, "batchMint should reject ETH");
    }

    function testBatchMintGas100() public {
        uint256 n = 100;
        address[] memory to = new address[](n);
        uint256[] memory soulIds = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) {
            to[i] = address(uint160(0x10000 + i));
            soulIds[i] = 0;
        }

        vm.prank(MINTER_ADDRESS);
        uint256 gasBefore = gasleft();
        sbt.batchMint(to, soulIds);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("batchMint gas for 100 items:", gasUsed);

        assertEq(sbt.totalSupply(0), n, "all 100 should be minted");
    }

    function testRecover() public {
        // only contract minter can transfer under the permision of the holder
        vm.prank(MINTER_ADDRESS);
        sbt.mint(alice, 0);
        vm.prank(alice);
        sbt.setApprovalForAll(owner, true);
        vm.prank(MINTER_ADDRESS);
        sbt.recover(alice, bob);
    }
}
