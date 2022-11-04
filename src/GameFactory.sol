// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "chainlink/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "chainlink/v0.8/interfaces/AutomationRegistryInterface1_2.sol";
import "chainlink/v0.8/interfaces/LinkTokenInterface.sol";

import "./DominationGame.sol";

interface KeeperRegistrarInterface {
  function register(
    string memory name,
    bytes calldata encryptedEmail,
    address upkeepContract,
    uint32 gasLimit,
    address adminAddress,
    bytes calldata checkData,
    uint96 amount,
    uint8 source,
    address sender
  ) external;
}


contract GameFactory {
    mapping(uint256 => address) public games;

    address deployer;
    address vrfCoordinator;
    address link;
    uint256 upkeepInterval;
    uint64 subscriptionId;
    bytes32 keyHash;

    LinkTokenInterface public immutable i_link;
    address public immutable registrar;
    AutomationRegistryInterface public immutable i_registry;
    bytes4 registerSig = KeeperRegistrarInterface.register.selector;

    event GameCreated(address indexed game, uint256 indexed upkeepId);
    event Receive(address indexed sender, uint256 indexed amount);
    event Fallback(address indexed sender, uint256 indexed amount);

    modifier onlyDeployer() {
        require(msg.sender == deployer, 'GameFactory: Only deployer can call this function');
        _;
    }

    constructor(uint64 _subscriptionId, address _vrfCoordinator, address _link, bytes32 _keyHash, uint256 _upkeepInterval, address _registrar, AutomationRegistryInterface _registry) {
        subscriptionId = _subscriptionId;
        vrfCoordinator = _vrfCoordinator;
        link = _link;
        keyHash = _keyHash;
        upkeepInterval = _upkeepInterval;
        deployer = msg.sender;
        registrar = _registrar;
        i_registry = _registry;
        i_link = LinkTokenInterface(_link);
    }

    function deployNewGame(bytes calldata encryptedEmail, bytes calldata checkData) external onlyDeployer {
        DominationGame game = new DominationGame(vrfCoordinator, link, keyHash, subscriptionId, upkeepInterval);

        // Register Game as VRF Consumer
        VRFCoordinatorV2Interface(vrfCoordinator).addConsumer(subscriptionId, address(game));

        // Register Game as Keeper Automation Contract
        (uint256 upkeepID) = registerAndPredictID("Domination", encryptedEmail, address(game), 1_500_000, deployer, checkData, 5 ether, 0);

        emit GameCreated(address(game), upkeepID);
    }

    // https://documentation-woad-five.vercel.app/docs/chainlink-automation/register-upkeep/
    function registerAndPredictID(
        string memory name,
        bytes calldata encryptedEmail,
        address upkeepContract,
        uint32 gasLimit,
        address adminAddress,
        bytes calldata checkData,
        uint96 amount,
        uint8 source
    ) public returns (uint256 upkeepID) {
        (State memory state, Config memory _c, address[] memory _k) = i_registry.getState();
        uint256 oldNonce = state.nonce;
        bytes memory payload = abi.encode(
        name,
        encryptedEmail,
        upkeepContract,
        gasLimit,
        adminAddress,
        checkData,
        amount,
        source,
        address(this)
        );
        
        i_link.transferAndCall(registrar, amount, bytes.concat(registerSig, payload));
        (state, _c, _k) = i_registry.getState();
        uint256 newNonce = state.nonce;
        if (newNonce == oldNonce + 1) {
        upkeepID = uint256(
            keccak256(abi.encodePacked(blockhash(block.number - 1), address(i_registry), uint32(oldNonce)))
        );
        return upkeepID;
        } else {
        revert("auto-approve disabled");
        }
    }

    receive() external payable {
        emit Receive(msg.sender, msg.value);
    }

    fallback() external payable {
        emit Fallback(msg.sender, msg.value);
    }
}