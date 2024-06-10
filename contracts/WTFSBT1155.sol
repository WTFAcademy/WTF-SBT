// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

contract WTFSBT1155 is Ownable, Pausable, ERC1155Supply {
    /* ============ Libraries ============ */
    using Strings for uint256;

    /* ============ Events ============ */
    /// @notice This event is emitted when new minter address is added
    event MinterAdded(address indexed newMinter);
    /// @notice This event is emitted when old minter address is removed
    event MinterRemoved(address indexed oldMinter);
    /// @notice This event is emitted when treasury address changes
    event TreasuryTransferred(
        address indexed oldTreasury,
        address indexed newTreasury
    );
    /// @notice This event is to easily track which creator registered
    ///      which Soul tokens without having to store the mapping on-chain.
    event CreatedSoul(
        address indexed creator,
        uint256 tokenId,
        string soulName
    );
    /// @notice This event is emitted when user donates during minting
    event Donate(
        uint256 indexed soulID,
        address indexed donator,
        uint256 amount
    );
    /// @notice This event is emitted when user recovers the SBTs
    event Recover(address oldOwner, address newOwner, uint256[] soulIds);

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
    /**
     * @notice Initializes the contract with the given parameters
     * @param name_ The name of the collection
     * @param symbol_ The symbol of the collection
     * @param baseURI_ The base URI for the metadata
     * @param treasury_ The treasury address
     */
    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        address treasury_
    ) ERC1155("") Ownable(msg.sender) {
        _baseURI = baseURI_;
        name = name_;
        symbol = symbol_;
        treasury = treasury_;
    }

    receive() external payable {
        payable(treasury).transfer(msg.value);
    }

    /**
     * @dev Register a new SBT token type for people to claim
     * @param soulName_ The name for the SBT
     * @param description_ The description of the SBT
     * @param startDateTimestamp_ The timestamp to start the claim period
     * @param endDateTimestamp_ The timestamp to end the claim period (0 means no expire time)
     */
    function createSoul(
        string memory soulName_,
        string memory description_,
        uint256 startDateTimestamp_,
        uint256 endDateTimestamp_
    ) public onlyOwner whenNotPaused {
        SoulContainer memory soulMetadata;
        soulMetadata.soulName = soulName_;
        soulMetadata.description = description_;
        soulMetadata.creator = _msgSender();
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
    function isCreated(uint256 soulId) public view returns (bool) {
        return (soulId < latestUnusedTokenId);
    }

    /**
     * @dev Recover function, transfer all SBTs from the old owner address to new address
     * The access to this function needs to be controlled, only minter can call.
     * @param oldOwner The old owner address for SBT
     * @param newOwner The new owner address for SBT
     */
    function recover(
        address oldOwner,
        address newOwner
    ) external onlyMinter whenNotPaused {
        uint256 tokenCount = latestUnusedTokenId;
        uint256[] memory soulIdList = new uint256[](tokenCount);
        uint256[] memory addressBalances = new uint256[](tokenCount);
        uint256 count = 0;

        // Collect balances and token IDs, and count non-zero balances
        for (uint256 i = 0; i < tokenCount; ++i) {
            uint256 balance = balanceOf(oldOwner, i);
            if (balance > 0) {
                addressBalances[count] = balance;
                soulIdList[count] = i;
                count++;
            }
        }

        // Resize the arrays to remove unused slots
        assembly {
            mstore(soulIdList, count)
            mstore(addressBalances, count)
        }

        // Transfer all SBTs from old owner to new owner
        _safeBatchTransferFrom(
            oldOwner,
            newOwner,
            soulIdList,
            addressBalances,
            ""
        );

        emit Recover(oldOwner, newOwner, soulIdList);
    }

    /**
     * @notice Internal function to update token balances
     * @param from The address transferring the tokens
     * @param to The address receiving the tokens
     * @param ids The list of token IDs
     * @param values The list of token amounts
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override {
        // Ensure that the transfer is either minting, burning, or by an authorized address
        require(
            from == address(0) ||
                to == address(0) ||
                _msgSender() == owner() ||
                isMinter(_msgSender()),
            "Soulbound: Transfer failed!"
        );

        super._update(from, to, ids, values);
    }

    /* ============ Metadata Related Functions ============ */
    /**
     * @dev Returns the ERC1155 metadata URI for a specified token ID
     * @param soulId The ID of the Soul token
     * @return The metadata URI for the Soul token
     */
    function uri(
        uint256 soulId
    ) public view virtual override returns (string memory) {
        require(isCreated(soulId), "SoulID not created");
        return
            bytes(_baseURI).length > 0
                ? string(abi.encodePacked(_baseURI, soulId.toString()))
                : "";
    }

    /**
     * @dev Sets the SBT base URI
     * @param baseURI_ The new base URI
     */
    function setbaseURI(
        string memory baseURI_
    ) external onlyOwner whenNotPaused {
        _baseURI = baseURI_;
    }

    /**
     * @dev Returns the name for a given Soul token ID
     * @param soulId The ID of the Soul token
     * @return The name of the Soul token
     */
    function getSoulName(uint256 soulId) external view returns (string memory) {
        require(isCreated(soulId), "SoulID not created");
        return (soulIdToSoulContainer[soulId].soulName);
    }

    /**
     * @dev Returns the description for a given Soul token ID
     * @param soulId The ID of the Soul token
     * @return The description of the Soul token
     */
    function getSoulDescription(
        uint256 soulId
    ) external view returns (string memory) {
        require(isCreated(soulId), "SoulID not created");
        return (soulIdToSoulContainer[soulId].description);
    }

    /**
     * @dev Returns the registered timestamp for a given Soul token ID
     * @param soulId The ID of the Soul token
     * @return The registered timestamp of the Soul token
     */
    function getSoulRegisteredTimestamp(
        uint256 soulId
    ) external view returns (uint256) {
        require(isCreated(soulId), "SoulID not created");
        return (soulIdToSoulContainer[soulId].registeredTimestamp);
    }

    /**
     * @dev Returns the startTimestamp for a SBT with soulId.
     * @param soulId The ID of the Soul token
     * @return The start timestamp of the Soul token
     */
    function getSoulStartDateTimestamp(
        uint256 soulId
    ) external view returns (uint256) {
        require(isCreated(soulId), "SoulID not created");
        return (soulIdToSoulContainer[soulId].startDateTimestamp);
    }

    /**
     * @dev Returns the end timestamp for a given Soul token ID
     * @param soulId The ID of the Soul token
     * @return The end timestamp of the Soul token
     */
    function getSoulEndDateTimestamp(
        uint256 soulId
    ) external view returns (uint256) {
        require(isCreated(soulId), "SoulID not created");
        return (soulIdToSoulContainer[soulId].endDateTimestamp);
    }

    /* ============ Minter Related Functions ============ */
    /**
     * @dev Mints a SBT with a given soul ID to a target address
     * This function can only be called by minter.
     * @param to The address to mint the SBT to
     * @param soulId The ID of the Soul token
     */
    function mint(
        address to,
        uint256 soulId
    ) external payable onlyMinter whenNotPaused {
        // check: the SBT with soulId is created
        require(isCreated(soulId), "SoulId is not created yet");
        // check: mint has started
        uint256 startDateTimestamp = soulIdToSoulContainer[soulId]
            .startDateTimestamp;
        require(block.timestamp >= startDateTimestamp, "Mint has not started");
        // check: mint has not ended
        uint256 endDateTimestamp = soulIdToSoulContainer[soulId]
            .endDateTimestamp;
        require(
            endDateTimestamp == 0 || block.timestamp < endDateTimestamp,
            "Mint has ended"
        );
        // donate if msg.value > 0
        if (msg.value > 0) {
            payable(treasury).transfer(msg.value);
            emit Donate(soulId, tx.origin, msg.value);
        }
        // mint SBT
        _mint(to, soulId, 1, "");
    }

    /**
     * @dev Burns a given amount of a specific token ID from an account
     * @param account The account to burn the tokens from
     * @param id The ID of the token to burn
     * @param value The amount of tokens to burn
     */
    function burn(address account, uint256 id, uint256 value) public {
        if (
            account != _msgSender() && !isApprovedForAll(account, _msgSender())
        ) {
            revert ERC1155MissingApprovalForAll(_msgSender(), account);
        }

        _burn(account, id, value);
    }

    /**
     * @dev Burns a given amount of specific token IDs from an account
     * @param account The account to burn the tokens from
     * @param ids The list of token IDs to burn
     * @param values The list of amounts of tokens to burn
     */
    function burnBatch(
        address account,
        uint256[] memory ids,
        uint256[] memory values
    ) public {
        if (
            account != _msgSender() && !isApprovedForAll(account, _msgSender())
        ) {
            revert ERC1155MissingApprovalForAll(_msgSender(), account);
        }

        _burnBatch(account, ids, values);
    }

    /**
     * @dev Returns whether an address has the minter role
     * @param minter_ The address to check
     * @return True if the address is a minter, false otherwise
     */
    function isMinter(address minter_) public view returns (bool) {
        return _minters[minter_];
    }

    /**
     * @dev Adds a new minter
     * @param minter_ The address of the new minter
     */
    function addMinter(address minter_) external onlyOwner whenNotPaused {
        require(minter_ != address(0), "Minter must not be 0 address");
        require(!_minters[minter_], "Minter already exist");
        _minters[minter_] = true;
        emit MinterAdded(minter_);
    }

    /**
     * @dev Removes an existing minter
     * @param minter_ The address of the minter to remove
     */
    function removeMinter(address minter_) external onlyOwner whenNotPaused {
        require(_minters[minter_], "Minter does not exist");
        _minters[minter_] = false;
        emit MinterRemoved(minter_);
    }

    /**
     * @dev Pauses the contract
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev Changes the treasury address
     * @param treasury_ The new treasury address
     */
    function transferTreasury(
        address treasury_
    ) external onlyOwner whenNotPaused {
        address oldTreasury = treasury;
        treasury = treasury_;
        emit TreasuryTransferred(oldTreasury, treasury);
    }
}
