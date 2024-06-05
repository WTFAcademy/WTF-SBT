// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "./interfaces/ISoul.sol";

contract WTFSBT1155 is Ownable, Pausable, ISoul, ERC1155Supply{
    /* ============ Libraries ============ */
    using Strings for uint256;

    /* ============ Events ============ */
    /// @notice This event is emitted when new minter address is added
    event MinterAdded(address indexed newMinter);
    /// @notice This event is emitted when old minter address is removed
    event MinterRemoved(address indexed oldMinter);
    /// @notice This event is emitted when treasury address changes
    event TreasuryTransferred(address indexed user, address indexed newTreasury);
    /// @notice This event is to easily track which creator registered
    ///      which Soul tokens without having to store the mapping on-chain.
    event CreatedSoul(address indexed creator, uint256 tokenId, string soulName);
    /// @notice This event is emitted when user donates during minting
    event Donate(uint256 indexed soulID, address indexed donator, uint256 amount);


    /* ============ Modifiers ============ */
    /// @notice Only minter modifier
    modifier onlyMinter() {
        require(_minters[_msgSender()], "Only minters can mint.");
        _;
    }


    /* ============ Structs ============ */
    /// @notice Struct used to contain the full metadata of a SBT
    struct SoulContainer {
        string soulName;
        string description;
        address creator;
        uint256 mintPrice;
        uint256 registeredTimestamp;
        uint256 startDateTimestamp;
        uint256 endDateTimestamp;
    }


    /* ============ State Variables ============ */
    /// @notice treasury address
    address public treasury;
    /// @notice collection name
    string public name;
    /// @notice collection symbol
    string public symbol;
    /// @notice SBT base URI
    string private _baseURI; 
    /// @notice list of minter address
    mapping(address => bool) private _minters;
    /// @notice Mapping from Soul ID to Soul Metadata
    mapping(uint256 => SoulContainer) public soulIdToSoulContainer;
    /// @notice This value signifies the largest tokenId value that has not been used yet.
    /// Whenever we register a new token, we increment this value by one, so essentially the tokenID
    /// signifies the total number of types of tokens registered through this contract.
    uint256 public latestUnusedTokenId;

    /* ============ Functions ============ */
    constructor(string memory name_, string memory symbol_, string memory baseURI_, address treasury_) ERC1155(""){
        _baseURI = baseURI_;
        name = name_;
        symbol = symbol_;
        treasury = treasury_;
    }

    receive() external payable {
        payable(treasury).transfer(msg.value);
    }

    /// @notice Register new SBT token type for people to claim.
    /// @dev This just allowlists the tokens that are able to claim this particular token type, but it does not necessarily mint the token until later.
    /// @param soulName_: name for the SBT
    /// @param description_: description of the SBT
    /// @param startDateTimestamp_: Timestamp to start claim period
    /// @param endDateTimestamp_: Timestamp to end claim period (0 means no expire time)
    function createSoul(string memory soulName_, string memory description_, uint256 mintPrice_, uint256 startDateTimestamp_, uint256 endDateTimestamp_) public onlyOwner whenNotPaused {
        SoulContainer memory soulMetadata;
        soulMetadata.soulName = soulName_;
        soulMetadata.description = description_;
        soulMetadata.creator = _msgSender();
        soulMetadata.mintPrice = mintPrice_;
        soulMetadata.registeredTimestamp = block.timestamp;
        soulMetadata.startDateTimestamp = startDateTimestamp_;
        soulMetadata.endDateTimestamp = endDateTimestamp_;

        // Store the metadata into a mapping for viewing later
        soulIdToSoulContainer[latestUnusedTokenId] = soulMetadata;
        emit CreatedSoul(_msgSender(), latestUnusedTokenId, soulName_);

        // increment the latest unused TokenId because we now have an additionally registered token.
        latestUnusedTokenId++;
    }

    /// @notice Return a boolean indicating whether a SBT with soulId is already created.
    function isCreated(uint256 soulId) public view returns(bool){
        if(soulId < latestUnusedTokenId){
            return true;
        }else{
            return false;
        }
    }

    /// @notice Recover function, transfer all SBTs from the old owner address to new address.
    /// @dev The access to this function needs to be controled, i.e. only community multisig can call.
    ///      The caller needs approve from the old owner.
    /// @param oldOwner The old owner address for SBT.
    /// @param newOwner The new owner address for SBT.
    function recover(address oldOwner, address newOwner) external override onlyOwner whenNotPaused{
        // balance of oldOwner
        uint256[] memory addressBalances = new uint256[](latestUnusedTokenId);
        // Created soul ID list
        uint256[] memory soulIdList = new uint256[](latestUnusedTokenId);
        // loop over all created soul ID
        for (uint256 i = 0; i < latestUnusedTokenId; ++i) {
            addressBalances[i] = balanceOf(oldOwner, i);
            soulIdList[i] = i;
        }
        // transfer all SBT from old owner address to new owner address.
        safeBatchTransferFrom(oldOwner, newOwner, soulIdList, addressBalances, "");
    }
    
    /// @notice Override of the token transfer hook that blocks all transfers but the mint, burn, and recover.
    ///      This is a precursor to non-transferable tokens.
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override{
        require(
            (from == address(0) || to == address(0) || _msgSender() == owner()),
            "Non-Transferable!"
        );
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    /* ============ Metadata Related Functions ============ */
    /// @notice Returns the ERC1155 metadata uri for specified token id. The id need to be created.
    function uri(uint256 soulId) public view virtual override returns (string memory) {
        require(isCreated(soulId), "SoulID not created");
        return bytes(_baseURI).length > 0 ? string(abi.encodePacked(_baseURI, soulId.toString())) : "";
    }

    /// @notice Returns the SBT metadata uri for specified token id. The id need to be created.
    function soulURI(uint256 soulId) public view virtual override returns (string memory) {
        require(isCreated(soulId), "SoulID not created");
        return bytes(_baseURI).length > 0 ? string(abi.encodePacked(_baseURI, soulId.toString())) : "";
    }

    /// @notice Set SBT baseURI
    function setbaseURI(string memory baseURI_) external onlyOwner whenNotPaused {
        _baseURI = baseURI_;
    }

    /// @notice Returns the locking status of an Soulbound Token
    function locked(uint256 sbtId) external view override returns (bool){
        require(isCreated(sbtId), "SoulID not created");
        return true;
    }

    /// @notice Returns the name for id SBT.
    /// @dev This briefly describes what the particular id SBT is, i.e. "Participated ETHBogota 2022".
    /// @param soulId The identifier for a SBT.
    function getSoulName(uint256 soulId) external view override returns(string memory){
        require(isCreated(soulId), "SoulID not created");
        return(soulIdToSoulContainer[soulId].soulName);
    }

    /// @notice Returns the Description for a SBT with soulId.
    function getSoulDescription(uint256 soulId) external view returns(string memory){
        require(isCreated(soulId), "SoulID not created");
        return(soulIdToSoulContainer[soulId].description);
    }

    /// @notice Returns the mintPrice for a SBT with soulId.
    function getSoulMintPrice(uint256 soulId) external view returns(uint256){
        require(isCreated(soulId), "SoulID not created");
        return(soulIdToSoulContainer[soulId].mintPrice);
    }

    /// @notice Returns the registeredTimestamp for a SBT with soulId.
    function getSoulRegisteredTimestamp(uint256 soulId) external view returns(uint256){
        require(isCreated(soulId), "SoulID not created");
        return(soulIdToSoulContainer[soulId].registeredTimestamp);
    }

    /// @notice Returns the startTimestamp for a SBT with soulId.
    function getSoulStartDateTimestamp(uint256 soulId) external view returns(uint256){
        require(isCreated(soulId), "SoulID not created");
        return(soulIdToSoulContainer[soulId].startDateTimestamp);
    }
    
    /// @notice Returns the endTimestamp for a SBT with soulId.
    function getSoulEndDateTimestamp(uint256 soulId) external view returns(uint256){
        require(isCreated(soulId), "SoulID not created");
        return(soulIdToSoulContainer[soulId].endDateTimestamp);
    }

    /* ============ Minter Related Functions ============ */
    /// @notice Mint SBT with soulID to target adddress. This function can only be called by minter.
    function mint(address to, uint256 soulId) external payable onlyMinter whenNotPaused{
        // check: the SBT with soulId is created
        require(isCreated(soulId), "SoulId is not created yet");
        // check: mint has started
        uint256 startDateTimestamp = soulIdToSoulContainer[soulId].startDateTimestamp;
        require(block.timestamp >= startDateTimestamp, "mint has not started");
        // check: mint has not ended
        uint256 endDateTimestamp = soulIdToSoulContainer[soulId].endDateTimestamp;
        require(endDateTimestamp == 0 || block.timestamp < endDateTimestamp, "mint has ended");
        // check: msg.value >= mint price
        uint256 mintPrice = soulIdToSoulContainer[soulId].mintPrice;
        require(msg.value >= mintPrice, "ETH amount < mint price");
        // donate if msg.value > 0
        if(msg.value > 0){
            payable(treasury).transfer(msg.value);
            emit Donate(soulId, tx.origin, msg.value);
        }
        // mint SBT
        _mint(to, soulId, 1, "");
    }

    /// @notice Returns whether an address has minter role.
    function isMinter(address minter_) public view returns(bool){
        return _minters[minter_];
    }

    /// @notice Add a new minter.
    function addMinter(address minter_) external onlyOwner whenNotPaused {
        require(minter_ != address(0), "Minter must not be 0 address");
        require(!_minters[minter_], "Minter already exist");
        _minters[minter_] = true;
        emit MinterAdded(minter_);
    }

    /// @notice Remove a existing minter.
    function removeMinter(address minter_) external onlyOwner whenNotPaused{
        require(_minters[minter_], "Minter does not exist");
        _minters[minter_] = false;
        emit MinterRemoved(minter_);
    }

    /// @notice change treasury address.
    function transferTreasury(address treasury_) external onlyOwner whenNotPaused{
        treasury = treasury_;
        emit TreasuryTransferred(msg.sender, treasury);
    }    
}