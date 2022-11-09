// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./WTFSBT1155.sol";

contract WTFSBT1155Minter is Ownable{
    /* ============ Events ============ */
    /// @notice This event is emitted when new SBT is minted
    event SBTMinted(address indexed account, uint256 indexed soulId);
    /// @notice This event is emitted when signer address is changed    
    event SignerChanged(address indexed oldSigner, address indexed newSigner);

    /* ============ State Variables ============ */
    address public signer; // singer address
    WTFSBT1155 public wtfsbt; // WTF SBT ERC1155 contract address
    mapping(uint256 => mapping(address => bool)) public mintedAddress; // tracks minted address for each soul ID, so each address only mint once

    /* ============ Constructor ============ */
    /// @notice initialize WTFSBT1155 addresss and signer address
    constructor(address payable sbtAddr_, address signer_){
        wtfsbt = WTFSBT1155(sbtAddr_);
        signer = signer_;
    }

    /* ============ Public Functions ============ */
    /*
     * @dev concatenate mint account and soulId to msgHash
     * @param account: mint address
     * @param soulId: ERC1155 token id
     */
    function getMessageHash(address account, uint256 soulId) public pure returns(bytes32){
        return keccak256(abi.encodePacked(account, soulId));
    }

    /**
     * @dev Verify signature using ECDSA, return true if the signature is valid.
     */
    function verify(bytes32 ethSignedMessageHash, bytes memory signature) public view returns (bool) {
        return ECDSA.recover(ethSignedMessageHash, signature) == signer;
    }

    /* ============ External Functions ============ */
    
    /**
     * @dev mint token `soulId` to `account` if `signature` is valid. 
     * `msgHash` is concatenated by `soulId` and `account`.
     * @param account: mint account
     * @param soulId: ERC1155 token id
     */
    function mint(address account, uint256 soulId, bytes memory signature)
    external payable
    {
        // check: the account has not minted the SBT with soulId yet
        require(!mintedAddress[soulId][account], "Already minted!");
        
        // ECDSA verify
        bytes32 msgHash = getMessageHash(account, soulId);
        bytes32 ethSignedMessageHash = ECDSA.toEthSignedMessageHash(msgHash); 
        require(verify(ethSignedMessageHash, signature), "Invalid signature");

        // mint SBT with soulId to account
        wtfsbt.mint{ value: msg.value }(account, soulId);
        // record account has minted SBT with soulId
        mintedAddress[soulId][account] = true;
        // emit SBT Minted event
        emit SBTMinted(account, soulId);
    }

    /**
     * @dev change signer address. Only owner can call.
     * @param newSigner: address of new signer
     */
     function setSigner(address newSigner) external onlyOwner{
         emit SignerChanged(signer, newSigner);
         signer = newSigner;
     }
}
