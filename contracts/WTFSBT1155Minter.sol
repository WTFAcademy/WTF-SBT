// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";
import "./WTFSBT1155.sol";

contract WTFSBT1155Minter is Ownable, Nonces {
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;

    /* ============ Events ============ */
    /// @notice This event is emitted when signer address is changed
    event SignerChanged(address indexed oldSigner, address indexed newSigner);
    /// @notice This event is emitted when new SBT is minted
    event SBTMinted(
        address indexed to,
        uint256 indexed soulId,
        uint256 donation
    );

    /* ============ State Variables ============ */
    address public signer; // singer address
    WTFSBT1155 public wtfsbt; // WTF SBT ERC1155 contract address
    uint256 public immutable _cachedChainId;

    /* ============ Constructor ============ */
    /// @notice initialize WTFSBT1155 addresss and signer address
    constructor(address payable sbtAddr_, address signer_) Ownable(msg.sender) {
        wtfsbt = WTFSBT1155(sbtAddr_);
        signer = signer_;
        _cachedChainId = block.chainid;
    }

    /* ============ Public Functions ============ */
    // @dev verify whether a signature is valid
    function verifySignature(
        address to,
        uint256 soulId,
        uint256 mintPrice,
        uint256 deadline,
        uint256 chainId,
        uint256 nonces,
        bytes memory signature
    ) public view returns (bool) {
        // 生成用于签名的消息
        bytes32 message = keccak256(
            abi.encodePacked(to, soulId, mintPrice, deadline, chainId, nonces)
        );
        bytes32 ethSignedMessage = message.toEthSignedMessageHash();

        // 恢复签名者地址
        return signer == ethSignedMessage.recover(signature);
    }

    /* ============ External Functions ============ */
    /**
     * @dev mint token `soulId` to `account` if `signature` is valid.
     * `msgHash` is concatenated by `soulId` and `account`.
     * @param to: mint address
     * @param soulId: ERC1155 token id
     * @param mintPrice: token mint price
     * @param deadline: token mint deadline
     * @param signature: signature by signer
     */
    function mint(
        address to,
        uint256 soulId,
        uint256 mintPrice,
        uint256 deadline,
        bytes memory signature
    ) external payable {
        // check: the account has not minted the SBT with soulId yet
        require(wtfsbt.balanceOf(to, soulId) == 0, "Already minted!");
        // check: donation is higher than mint price
        require(msg.value >= mintPrice, "Donation too low");
        // check: signature not expired
        require(deadline >= block.timestamp, "Expired signature");
        // check: signature is valid
        require(
            verifySignature(
                to,
                soulId,
                mintPrice,
                deadline,
                _cachedChainId,
                _useNonce(to),
                signature
            ),
            "Invalid signature"
        );

        // mint SBT with soulId to account
        wtfsbt.mint{value: msg.value}(to, soulId);
        // emit SBT Minted event
        emit SBTMinted(to, soulId, msg.value);
    }

    /**
     * @dev recover sbt to new address. only owner can call.
     * @param oldOwner The old owner address for SBT.
     * @param newOwner The new owner address for SBT.
     */
    function recover(address oldOwner, address newOwner) external onlyOwner {
        wtfsbt.recover(oldOwner, newOwner);
    }

    /**
     * @dev change signer address. only owner can call.
     * @param newSigner: address of new signer
     */
    function setSigner(address newSigner) external onlyOwner {
        signer = newSigner;
        emit SignerChanged(signer, newSigner);
    }

    // withdraw eth
    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}
