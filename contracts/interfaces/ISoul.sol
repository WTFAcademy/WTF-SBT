// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/**
 * @title Compatible Soulbound Token Standard
 * Note: The Compatible Soulbound Token Standard provieds following features for SBT:
 * 1. Non-transferrable
 * 2. SBTs can be recovered in "extreme" circumstances, i.e. privite key exploited
 * 3. Compatible with popular NFT standards: ERC721/ERC1155
 */

interface ISoul {
    /* ============ Events ============ */
    /// @notice Emitted when the locking status is changed to locked.
    /// @dev If a token is minted and the status is locked, this event should be emitted.
    /// @param sbtId The identifier for an SBT.
    event Bound(uint256 sbtId);

    /// @notice Emitted when the locking status is changed to unlocked.
    /// @dev If a token is minted and the status is unlocked, this event should be emitted.
    /// @param sbtId The identifier for an SBT.
    event Unbound(uint256 sbtId);

    /// @notice Emitted when the locking status is changed to unlocked.
    /// @dev If a token is minted and the status is unlocked, this event should be emitted.
    /// @param oldOwner The old owner address for SBT.
    /// @param newOwner The new owner address for SBT.
    event Recover(address oldOwner, address newOwner);

    /* ============ Functions ============ */
    /// @notice Returns the name for id SBT.
    /// @dev This briefly describes what the particular id SBT is, i.e. "Participated ETHBogota 2022".
    /// @param sbtId The identifier for an SBT.
    function getSoulName(uint256 sbtId) external view returns(string memory);
    
    /// @notice Returns the locking status of an Soulbound Token
    /// @param sbtId The identifier for an SBT.
    function locked(uint256 sbtId) external view returns (bool);

    /// @notice Returns the Uniform Resource Identifier (URI) for id SBT.
    /// @dev This is compatible to ERC721 tokenURI function and ERC721 URI function.
    /// @param sbtId The identifier for an SBT.
    function soulURI(uint256 sbtId) external view returns(string memory);

    /// @notice Recover function, transfer all SBTs from the old owner address to new address.
    /// @dev The access to this function needs to be controled, i.e. only community multisig can call.
    /// @param oldOwner The old owner address for SBT.
    /// @param newOwner The new owner address for SBT.
    function recover(address oldOwner, address newOwner) external;
}
