// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

interface IBaseCharacterNFT is IERC721 {
    function tokensOwnedBy(address who) external view returns (uint256[] memory);
    function ownerOf(uint256 tokenId) view external returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function mint(address to) payable external;
}
