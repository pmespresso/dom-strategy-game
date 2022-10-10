-include .env

build:; forge build --via-ir --optimize

test :; forge test --via-ir -vvv

snapshot :; forge snapshot

deploy-anvil :; forge script script/DeployGame.s.sol:DeployGame --rpc-url http://127.0.0.1:8545 --broadcast -vvv --via-ir --private-key=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

deploy-mumbai :; forge script script/DeployGame.s.sol:DeployGame --fork-url ${MUMBAI_RPC_URL} --via-ir --private-key=${MUMBAI_PRIVATE_KEY} --gas-limit=7500000 --verify --optimize --optimizer-runs 200 --broadcast --use 0.8.16 --etherscan-api-key ${POLYGONSCAN_API_KEY} -vvvv

deploy-base-char-mumbai :; forge script script/DeployBaseCharacter.s.sol:DeployBaseCharacter --fork-url ${MUMBAI_RPC_URL} --via-ir --private-key=${MUMBAI_PRIVATE_KEY} --gas-limit=7500000 --verify --optimize --optimizer-runs 200 --broadcast --use 0.8.16 --etherscan-api-key ${POLYGONSCAN_API_KEY} -vvvv

deploy-keepr-mumbai :; forge script script/DeployKeeprMumbai.s.sol:DeployKeeprMumbai --fork-url ${MUMBAI_RPC_URL} --via-ir --private-key=${MUMBAI_PRIVATE_KEY} --gas-limit=7500000 --verify --optimize --optimizer-runs 200 --broadcast --use 0.8.16 --etherscan-api-key ${POLYGONSCAN_API_KEY} -vvvv