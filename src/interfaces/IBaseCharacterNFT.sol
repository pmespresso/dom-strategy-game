// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IBaseCharacterNFT {
    function tokensOwnedBy() external view returns (uint256[] memory);
    function ownerOf(uint256 tokenId) view external returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function mint(address to) external;
}
