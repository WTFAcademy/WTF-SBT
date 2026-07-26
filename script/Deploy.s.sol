// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/WTFSBT1155.sol";
import "../contracts/WTFSBT1155Minter.sol";

/**
 * @notice Deploys WTFSBT1155 + WTFSBT1155Minter and wires them together.
 *
 * Required environment variables:
 *   TREASURY  - address receiving donations
 *   SIGNER    - backend signing address (must match the backend SBT.PrivateKey)
 * Optional:
 *   SBT_NAME     (default "WTF Certificates")
 *   SBT_SYMBOL   (default "WTFC")
 *   SBT_BASE_URI (default "https://api.wtf.academy/v1/sbt/token/")
 *
 * BNB Chain mainnet:
 *   forge script script/Deploy.s.sol --rpc-url bsc \
 *     --broadcast --verify --private-key $DEPLOYER_KEY
 * BNB Chain testnet:
 *   forge script script/Deploy.s.sol --rpc-url bsc_testnet \
 *     --broadcast --private-key $DEPLOYER_KEY
 *
 * After deploy, register each certificate with sbt.createSoul(...) and keep
 * soulId -> course mapping in sync with the backend SBT.SoulCourse config.
 */
contract Deploy is Script {
    function run() external {
        address treasury = vm.envAddress("TREASURY");
        address signer = vm.envAddress("SIGNER");
        string memory name_ = vm.envOr("SBT_NAME", string("WTF Certificates"));
        string memory symbol_ = vm.envOr("SBT_SYMBOL", string("WTFC"));
        string memory baseURI = vm.envOr(
            "SBT_BASE_URI",
            string("https://api.wtf.academy/v1/sbt/token/")
        );

        vm.startBroadcast();
        WTFSBT1155 sbt = new WTFSBT1155(name_, symbol_, baseURI, treasury);
        WTFSBT1155Minter minter = new WTFSBT1155Minter(
            payable(address(sbt)),
            signer
        );
        sbt.addMinter(address(minter));
        vm.stopBroadcast();

        console.log("WTFSBT1155:       ", address(sbt));
        console.log("WTFSBT1155Minter: ", address(minter));
        console.log("chainid:          ", block.chainid);
    }
}
