// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/WTFSBT1155Minter.sol";

contract WTFSBT1155MinterTest is Test {
    using MessageHashUtils for bytes32;
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
        sbt = new WTFSBT1155(
            "Test SBT",
            "TestSBT",
            "https://api.wtf.academy/token",
            msg.sender
        );
        sbt.createSoul("test01", "test 01", 0, 0);
        sbt.createSoul(
            "test02",
            "test 02",
            block.timestamp,
            block.timestamp + 100
        );

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
        uint256 mintPrice_ = 0;
        uint256 deadline_ = block.timestamp + 100;
        uint256 chainId_ = minter._cachedChainId();
        uint256 nonce_ = 0;
        // ECDSA verify
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                alice,
                soulID_,
                mintPrice_,
                deadline_,
                chainId_,
                nonce_
            )
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, msgHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(alice);
        minter.mint(alice, 0, mintPrice_, deadline_, signature);
        assertEq(sbt.balanceOf(alice, 0), 1);
    }

    function testExpiredSignature() public {
        uint256 soulID_ = 1;
        uint256 mintPrice_ = 1 ether;
        uint256 deadline_ = block.timestamp - 1; // Set deadline in the past
        uint256 chainId_ = minter._cachedChainId();
        uint256 nonce_ = 0;

        bytes32 msgHash = keccak256(
            abi.encodePacked(
                alice,
                soulID_,
                mintPrice_,
                deadline_,
                chainId_,
                nonce_
            )
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, msgHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(alice);
        vm.expectRevert("Expired signature");
        minter.mint(alice, soulID_, mintPrice_, deadline_, signature);
    }

    function testInvalidDonationAmount() public {
        uint256 soulID_ = 1;
        uint256 mintPrice_ = 1 ether;
        uint256 deadline_ = block.timestamp + 100;
        uint256 chainId_ = minter._cachedChainId();
        uint256 nonce_ = 0;

        bytes32 msgHash = keccak256(
            abi.encodePacked(
                alice,
                soulID_,
                mintPrice_,
                deadline_,
                chainId_,
                nonce_
            )
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, msgHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.deal(alice, 0.5 ether); // Alice has less than required donation
        vm.prank(alice, alice);
        vm.expectRevert("Donation too low");
        minter.mint{value: 0.5 ether}(
            alice,
            soulID_,
            mintPrice_,
            deadline_,
            signature
        );
    }

    function testWithdrawal() public {
        vm.deal(address(minter), 10 ether); // Mock sending ether to minter contract

        uint256 preBalance = owner.balance;
        vm.prank(owner);
        minter.withdraw();
        uint256 postBalance = owner.balance;

        assertEq(
            postBalance - preBalance,
            10 ether,
            "Withdrawal amount incorrect"
        );
    }

    function testUnauthorizedMinter() public {
        uint256 soulID_ = 0;
        uint256 mintPrice_ = 0;
        uint256 deadline_ = block.timestamp + 100;
        uint256 chainId_ = minter._cachedChainId();
        uint256 nonce_ = 0;

        bytes32 msgHash = keccak256(
            abi.encodePacked(
                bob,
                soulID_,
                mintPrice_,
                deadline_,
                chainId_,
                nonce_
            )
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, msgHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(bob);
        vm.expectRevert("Invalid signature");
        minter.mint(bob, soulID_, mintPrice_, deadline_, signature);
    }

    function testChangeSigner() public {
        address newSigner = address(0xB0B);
        vm.prank(owner);
        minter.setSigner(newSigner);
        assertEq(minter.signer(), newSigner, "Signer should be changed");

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        minter.setSigner(alice);
    }

    function testMintAfterPause() public {
        vm.prank(owner);
        sbt.pause();
        vm.expectRevert("Pausable: paused");
        vm.prank(address(minter));
        sbt.mint(alice, 0);

        vm.prank(owner);
        sbt.unpause();
        vm.prank(address(minter));
        sbt.mint(alice, 0);
        assertEq(sbt.balanceOf(alice, 0), 1, "Alice should have 1 token");
    }

    function testRecoverWithNoTokens() public {
        vm.prank(owner);
        vm.expectRevert("No tokens to recover");
        minter.recover(alice, bob);
    }

    function testRecoverWithoutApproval() public {
        vm.prank(address(minter));
        sbt.mint(alice, 0);
        vm.expectRevert("ERC1155: caller is not owner nor approved");
        vm.prank(bob);
        minter.recover(alice, bob);
    }

    function testNonceReusage() public {
        uint256 soulID_ = 0;
        uint256 mintPrice_ = 0;
        uint256 deadline_ = block.timestamp + 100;
        uint256 chainId_ = minter._cachedChainId();
        uint256 nonce_ = minter.nonces(alice);

        bytes32 msgHash = keccak256(
            abi.encodePacked(
                alice,
                soulID_,
                mintPrice_,
                deadline_,
                chainId_,
                nonce_
            )
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, msgHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // First mint should work
        vm.prank(alice);
        minter.mint(alice, soulID_, mintPrice_, deadline_, signature);
        assertEq(sbt.balanceOf(alice, soulID_), 1, "Alice should have 1 token");

        soulID_ = 1;
        msgHash = keccak256(
            abi.encodePacked(
                alice,
                soulID_,
                mintPrice_,
                deadline_,
                chainId_,
                nonce_
            )
        ).toEthSignedMessageHash();
        (v, r, s) = vm.sign(ownerPrivateKey, msgHash);
        signature = abi.encodePacked(r, s, v);

        // Attempt to reuse the same nonce for a second mint should fail
        vm.expectRevert("Invalid nonce");
        vm.prank(alice);
        minter.mint(alice, soulID_, mintPrice_, deadline_, signature);
    }
}
