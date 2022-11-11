// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "chainlink/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "chainlink/v0.8/interfaces/AutomationRegistryInterface1_2.sol";
import "chainlink/v0.8/interfaces/LinkTokenInterface.sol";
import "chainlink/v0.8/interfaces/OwnableInterface.sol";

import "./HelperConfig.sol";

/***
    This script would be able to dynamically register upkeeps if it were the owner of the registrar, however, it is not. Only the owner can approve registration requests.

 */

interface KeeperRegistrarInterface is OwnableInterface {
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
    function setAutoApproveAllowedSender(address senderAddress, bool allowed) external;
    function approve(string memory name, address upkeepContract, uint32 gasLimit, address adminAddress, bytes calldata checkData, bytes32 hash) external;
    function getPendingRequest(bytes32 hash) external view returns (address, uint96);
}

contract RegisterChainlinkServices is Script {
    LinkTokenInterface public i_link;
    KeeperRegistrarInterface public i_registrar;
    AutomationRegistryInterface public i_registry;
    bytes4 registerSig = KeeperRegistrarInterface.register.selector;

    function run() external {
        HelperConfig helperConfig = new HelperConfig();

        (
        ,
        ,
        ,
        address link, 
        ,
        address keeperRegistry,
        address keeperRegistrar,
        ,
        ,
        ,
        ) = helperConfig.activeNetworkConfig();

        address deployer = vm.envAddress("MUMBAI_ADDRESS");

        console.log("Deployer: ", deployer);

        address game = vm.envAddress("GAME");
        address bot1 = vm.envAddress("BOT1");
        address bot2 = vm.envAddress("BOT2");
        
        vm.startBroadcast();

        i_registrar = KeeperRegistrarInterface(keeperRegistrar);
        i_registry = AutomationRegistryInterface(keeperRegistry);
        i_link = LinkTokenInterface(link);

        bytes memory encryptedEmail = "0x";
        bytes memory checkData = "0x";

        (uint256 gameUpkeepID) = registerAndPredictID("Domination", encryptedEmail, game, 1_500_000, deployer, checkData, 5 ether, 0);
        (uint256 horizontalBot1UpkeepId) = registerAndPredictID("Horizontal Bot 1", encryptedEmail, bot1, 1_500_000, deployer, checkData, 5 ether, 0);
        (uint256 horizontalBot2UpkeepId) = registerAndPredictID("Horizontal Bot 2", encryptedEmail, bot2, 1_500_000, deployer, checkData, 5 ether, 0);

        console.log("horizontalBot1UpkeepId ", horizontalBot1UpkeepId);
        console.log("horizontalBot2UpkeepId ", horizontalBot2UpkeepId);
        console.log("gameUpkeepID ", gameUpkeepID);

        vm.stopBroadcast();
    }

    // https://documentation-woad-five.vercel.app/docs/chainlink-automation/register-upkeep/
    function registerAndPredictID(
        string memory name,
        bytes memory encryptedEmail,
        address upkeepContract,
        uint32 gasLimit,
        address adminAddress,
        bytes memory checkData,
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

        address owner = i_registrar.owner();

        console.log("registrar owner", owner);

        console.log("Old Nonce => ", oldNonce);

        bytes32 hash = keccak256(abi.encode(upkeepContract, gasLimit, adminAddress, checkData));
        
        console.log("---- hash ----");
        console.logBytes32(hash);

        (bool success, ) = address(adminAddress).call(abi.encodeWithSelector(i_link.transferAndCall.selector, address(i_registrar), amount, bytes.concat(registerSig, payload)));

        (address pendingRequestAdmin, uint96 pendingRequestBalance) = i_registrar.getPendingRequest(hash);

        console.log("Pending Request Admin => ", pendingRequestAdmin);
        console.log("Pending Request Balance => ", pendingRequestBalance);
        
        (success, ) = address(adminAddress).call(
            abi.encodeWithSelector(
                    i_registrar.approve.selector,
                    name, upkeepContract, gasLimit, adminAddress, checkData, hash
                )
            );

        (state, _c, _k) = i_registry.getState();
        uint256 newNonce = state.nonce;
        console.log("New nonce => ", newNonce);

        if (newNonce == oldNonce + 1) {
            upkeepID = uint256(
                keccak256(abi.encodePacked(blockhash(block.number - 1), address(i_registry), uint32(oldNonce)))
            );
            return upkeepID;
        } else {
            console.log("approve failed");
        }
    }
}