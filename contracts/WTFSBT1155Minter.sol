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
    /**
     * @dev This event is emitted when the signer address is changed
     * @param oldSigner The address of the old signer
     * @param newSigner The address of the new signer
     */
    event SignerChanged(address indexed oldSigner, address indexed newSigner);
    /**
     * @notice This event is emitted when a new SBT is minted
     * @param to The address to which the SBT is minted
     * @param soulId The ID of the SBT
     * @param donation The donation amount sent during the mint
     */
    event SBTMinted(
        address indexed to,
        uint256 indexed soulId,
        uint256 donation
    );

    /* ============ State Variables ============ */
    address public signer; // Signer address
    WTFSBT1155 public wtfsbt; // WTF SBT ERC1155 contract address
    uint256 public immutable _cachedChainId; // Cached chain ID for replay protection

    /* ============ Constructor ============ */
    /**
     * @dev Initializes the WTFSBT1155 contract address and signer address
     * @param sbtAddr_ The address of the WTFSBT1155 contract
     * @param signer_ The address of the initial signer
     */
    constructor(address payable sbtAddr_, address signer_) Ownable(msg.sender) {
        wtfsbt = WTFSBT1155(sbtAddr_);
        signer = signer_;
        _cachedChainId = block.chainid;
    }

    /* ============ Public Functions ============ */
    /**
     * @dev Verifies whether a signature is valid
     * @param to The address to which the SBT will be minted
     * @param soulId The ID of the SBT
     * @param mintPrice The price of minting the SBT
     * @param deadline The deadline until which the signature is valid
     * @param chainId The chain ID for replay protection
     * @param nonces The nonce to prevent replay attacks
     * @param signature The signature to verify
     * @return True if the signature is valid, false otherwise
     */
    function verifySignature(
        address to,
        uint256 soulId,
        uint256 mintPrice,
        uint256 deadline,
        uint256 chainId,
        uint256 nonces,
        bytes memory signature
    ) public view returns (bool) {
        // Generate the message for signature
        bytes32 message = keccak256(
            abi.encodePacked(to, soulId, mintPrice, deadline, chainId, nonces)
        );
        bytes32 ethSignedMessage = message.toEthSignedMessageHash();

        // Recover the address of the signer
        return signer == ethSignedMessage.recover(signature);
    }

    /* ============ External Functions ============ */
    /**
     * @dev Mints a token `soulId` to `to` if the `signature` is valid
     * @param to The address to which the SBT will be minted
     * @param soulId The ID of the SBT
     * @param mintPrice The price of minting the SBT
     * @param deadline The deadline until which the signature is valid
     * @param signature The signature to verify
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
     * @dev Recovers SBTs to a new address. Only the owner can call this function.
     * @param oldOwner The old owner address for SBT
     * @param newOwner The new owner address for SBT
     */
    function recover(address oldOwner, address newOwner) external onlyOwner {
        wtfsbt.recover(oldOwner, newOwner);
    }

    /**
     * @dev Changes the signer address. Only the owner can call this function.
     * @param newSigner The address of the new signer
     */
    function setSigner(address newSigner) external onlyOwner {
        signer = newSigner;
        emit SignerChanged(signer, newSigner);
    }

    /**
     * @dev Withdraws the contract's balance. Only the owner can call this function.
     */
    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}
