// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "solmate/tokens/ERC721.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

contract BaseCharacter is ERC721 {
    using Strings for uint256;

    string baseURI;
    uint256 currentTokenId;
    
    mapping (address => uint256[]) public tokensOwnedBy;
    
    error NonExistentTokenUri();

    event Received(address indexed who, uint256 indexed amount);

    constructor() ERC721("Domination Character Base", "DOM") {
        currentTokenId = 1;
    }

    function mint(address to) payable external {
        require(msg.value >= 0.01 ether, "You need to pay at least 0.01 Ether to mint.");
        _mint(to, currentTokenId);
        currentTokenId += 1;
        tokensOwnedBy[to].push(currentTokenId);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (ownerOf(tokenId) == address(0)) {
            revert NonExistentTokenUri();
        }

        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    function setBaseURI(string memory _baseURI) external {
        baseURI = _baseURI;
    }

    receive() external payable {
        // React to receiving ether
        emit Received(msg.sender, msg.value);
    }
}
