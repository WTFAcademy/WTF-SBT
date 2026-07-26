// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/WTFSBT1155.sol";
import "../script/Airdrop.s.sol";

/// @notice Test harness over the real Airdrop script. Only the configuration seams are
/// overridden — all loading, preflight and chunking logic under test is the production code.
/// Env vars are deliberately avoided here: they are process-global and shared across test
/// cases, so driving them per test is unreliable.
contract AirdropHarness is Airdrop {
    address internal _sbt;
    string internal _file;
    uint256 internal _chunk;
    string internal _map;

    constructor(
        address sbt_,
        string memory file_,
        uint256 chunk_,
        string memory map_
    ) {
        _sbt = sbt_;
        _file = file_;
        _chunk = chunk_;
        _map = map_;
    }

    function _sbtAddress() internal view override returns (address) {
        return _sbt;
    }

    function _holdersFile() internal view override returns (string memory) {
        return _file;
    }

    function _chunkSize() internal view override returns (uint256) {
        return _chunk;
    }

    function _soulIdMapJson() internal view override returns (string memory) {
        return _map;
    }
}

/// @notice End-to-end exercise of script/Airdrop.s.sol against a locally deployed SBT,
/// using airdrop/base-holders.example.json as the fixture: 5 entries over 3 distinct
/// recipients — soul 0 to A, B, C and soul 1 to A, B.
contract AirdropScriptTest is Test {
    WTFSBT1155 public sbt;

    address owner = address(1234);

    string constant FIXTURE = "airdrop/base-holders.example.json";
    address constant HOLDER_A = 0x11346Aa19b6553DC3508F04015B4c2c749380D50;
    address constant HOLDER_B = 0x36390b9B8C16299D51565B70551419ea06E051A6;
    address constant HOLDER_C = 0x8ba1f109551bD432803012645Ac136ddd64DBA72;

    function setUp() public {
        vm.startPrank(owner);
        sbt = new WTFSBT1155(
            "WTF Certificates",
            "WTFC",
            "https://api.wtf.academy/v1/sbt/token/",
            owner
        );
        // same order as Base: soul 0 then soul 1
        sbt.createSoul("base-soul-0", "migrated from Base", 0, 0);
        sbt.createSoul("base-soul-1", "migrated from Base", 0, 0);
        vm.stopPrank();
    }

    /// @dev Default harness: chunk size 2 over 5 entries, i.e. 3 chunks, no soulId remap.
    function _harness() internal returns (AirdropHarness) {
        return new AirdropHarness(address(sbt), FIXTURE, 2, "");
    }

    /// @dev The script's preflight checks msg.sender, but vm.startBroadcast switches the
    /// caller of the subsequent batchMint calls to the broadcaster, so grant both.
    function _addMinter(address minter) internal {
        vm.prank(owner);
        sbt.addMinter(minter);
        if (minter != DEFAULT_SENDER) {
            vm.prank(owner);
            sbt.addMinter(DEFAULT_SENDER);
        }
    }

    function testAirdropRevertsWhenSenderIsNotMinter() public {
        // the script's preflight must tell the operator to call addMinter first
        AirdropHarness airdrop = _harness();
        vm.expectRevert(
            bytes(
                "Airdrop: broadcasting EOA is not a minter. As the contract owner call sbt.addMinter(<airdropEOA>) before running this script, and sbt.removeMinter(<airdropEOA>) after it finishes."
            )
        );
        airdrop.run();
    }

    function testAirdropMintsEveryHolder() public {
        AirdropHarness airdrop = _harness();
        _addMinter(address(this));
        airdrop.run();

        assertEq(sbt.balanceOf(HOLDER_A, 0), 1, "A should hold soul 0");
        assertEq(sbt.balanceOf(HOLDER_B, 0), 1, "B should hold soul 0");
        assertEq(sbt.balanceOf(HOLDER_C, 0), 1, "C should hold soul 0");
        assertEq(sbt.balanceOf(HOLDER_A, 1), 1, "A should hold soul 1");
        assertEq(sbt.balanceOf(HOLDER_B, 1), 1, "B should hold soul 1");
        assertEq(sbt.balanceOf(HOLDER_C, 1), 0, "C should not hold soul 1");
        assertEq(sbt.totalSupply(0), 3, "soul 0 supply");
        assertEq(sbt.totalSupply(1), 2, "soul 1 supply");
    }

    function testAirdropIsIdempotent() public {
        AirdropHarness airdrop = _harness();
        _addMinter(address(this));
        airdrop.run();
        // a full re-run must not double-mint anything
        airdrop.run();

        assertEq(sbt.totalSupply(0), 3, "soul 0 supply unchanged");
        assertEq(sbt.totalSupply(1), 2, "soul 1 supply unchanged");
        assertEq(sbt.balanceOf(HOLDER_A, 0), 1, "A still holds exactly 1");
    }

    function testAirdropResumesPartialRun() public {
        AirdropHarness airdrop = _harness();
        _addMinter(address(this));
        // simulate a run that died after the first two mints
        sbt.mint(HOLDER_A, 0);
        sbt.mint(HOLDER_B, 0);

        airdrop.run();

        assertEq(sbt.balanceOf(HOLDER_A, 0), 1, "A not double-minted");
        assertEq(sbt.balanceOf(HOLDER_B, 0), 1, "B not double-minted");
        assertEq(sbt.totalSupply(0), 3, "soul 0 supply");
        assertEq(sbt.totalSupply(1), 2, "soul 1 supply");
    }

    function testAirdropSingleChunk() public {
        // chunk size larger than the file: one batchMint call for everything
        AirdropHarness airdrop = new AirdropHarness(
            address(sbt),
            FIXTURE,
            1000,
            ""
        );
        _addMinter(address(this));
        airdrop.run();
        assertEq(sbt.totalSupply(0), 3, "soul 0 supply");
        assertEq(sbt.totalSupply(1), 2, "soul 1 supply");
    }

    function testAirdropSoulIdMap() public {
        // create two extra souls so Base 0/1 can be remapped to BSC 2/3
        vm.startPrank(owner);
        sbt.createSoul("bsc-soul-2", "remapped", 0, 0);
        sbt.createSoul("bsc-soul-3", "remapped", 0, 0);
        vm.stopPrank();

        AirdropHarness airdrop = new AirdropHarness(
            address(sbt),
            FIXTURE,
            2,
            '{"0":"2","1":"3"}'
        );
        _addMinter(address(this));
        airdrop.run();

        assertEq(sbt.totalSupply(0), 0, "original soul 0 untouched");
        assertEq(sbt.totalSupply(1), 0, "original soul 1 untouched");
        assertEq(sbt.totalSupply(2), 3, "remapped soul 2 supply");
        assertEq(sbt.totalSupply(3), 2, "remapped soul 3 supply");
        assertEq(sbt.balanceOf(HOLDER_C, 2), 1, "C should hold remapped soul 2");
    }

    function testAirdropSoulIdMapPassesThroughUnlistedIds() public {
        vm.prank(owner);
        sbt.createSoul("bsc-soul-2", "remapped", 0, 0);

        // only Base soul 1 is remapped; soul 0 must pass through unchanged
        AirdropHarness airdrop = new AirdropHarness(
            address(sbt),
            FIXTURE,
            2,
            '{"1":"2"}'
        );
        _addMinter(address(this));
        airdrop.run();

        assertEq(sbt.totalSupply(0), 3, "soul 0 passed through");
        assertEq(sbt.totalSupply(1), 0, "soul 1 remapped away");
        assertEq(sbt.totalSupply(2), 2, "soul 2 received the remap");
    }

    function testAirdropRevertsOnUncreatedSoulId() public {
        // map Base soul 1 to a soulId that does not exist on this chain
        AirdropHarness airdrop = new AirdropHarness(
            address(sbt),
            FIXTURE,
            2,
            '{"1":"9"}'
        );
        _addMinter(address(this));
        vm.expectRevert(
            bytes(
                "Airdrop: soulId 9 does not exist on this chain (latestUnusedTokenId=2). Run createSoul() in the same order as Base, or set SOUL_ID_MAP."
            )
        );
        airdrop.run();
    }

    function testAirdropRevertsWhenPaused() public {
        AirdropHarness airdrop = _harness();
        _addMinter(address(this));
        vm.prank(owner);
        sbt.pause();

        vm.expectRevert(bytes("Airdrop: contract is paused, call unpause()"));
        airdrop.run();
    }

    function testAirdropRevertsOnZeroChunkSize() public {
        AirdropHarness airdrop = new AirdropHarness(
            address(sbt),
            FIXTURE,
            0,
            ""
        );
        _addMinter(address(this));
        vm.expectRevert(bytes("CHUNK_SIZE must be > 0"));
        airdrop.run();
    }
}
