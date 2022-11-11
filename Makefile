-include .env

build:; forge build --via-ir --optimize

test :; forge test --via-ir -vvv

snapshot :; forge snapshot

deploy-anvil :; forge script script/DeployGame.s.sol:DeployGame --rpc-url http://127.0.0.1:8545 --broadcast -vvv --via-ir --private-key=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

deploy-bots :; forge script script/DeployBots.s.sol:DeployBots --fork-url ${MUMBAI_RPC_URL} --via-ir --private-key=${MUMBAI_PRIVATE_KEY} --optimize --optimizer-runs 200 --broadcast --verify --use 0.8.17 --etherscan-api-key ${POLYGONSCAN_API_KEY} -vvvv

verify-bot1 :; forge verify-contract 0xC7f2Cf4845C6db0e1a1e91ED41Bcd0FcC1b0E141 src/HorizontalBot.sol:HorizontalBot --constructor-args 0x000000000000000000000000de142252d021012371a192f744ce6b0b064938080000000000000000000000008acd9fffa9f887521f02e4078de94806b478c95e000000000000000000000000000000000000000000000000000000000000012c --watch --optimizer-runs 200 --compiler-version "v0.8.17+commit.8df45f5" --chain mumbai

seed-balances :; forge script script/SeedBalances.s.sol:SeedBalances --fork-url ${MUMBAI_RPC_URL} --via-ir --private-key=${MUMBAI_PRIVATE_KEY} --optimize --optimizer-runs 200 --broadcast --use 0.8.17 --etherscan-api-key ${POLYGONSCAN_API_KEY} -vvvv

register-consumers :; forge script script/RegisterVRFConsumers.s.sol:RegisterVRFConsumers --fork-url ${MUMBAI_RPC_URL} --via-ir --private-key=${MUMBAI_PRIVATE_KEY} --optimize --optimizer-runs 200 --broadcast --use 0.8.17 --etherscan-api-key ${POLYGONSCAN_API_KEY} -vvvv

# verify-game :; forge verify-contract --watch 0xC5A92BD880d5020f14e8e737E0c37e73763Ab751 src/DominationGame.sol:DominationGame ${POLYGONSCAN_API_KEY}
# verify-game :; forge verify-contract 0xC5A92BD880d5020f14e8e737E0c37e73763Ab751 DominationGame --watch
# deploy-game :; forge create --rpc-url ${MUMBAI_RPC_URL}  \
#  --constructor-args 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed 0x326C977E6efc84E512bB9C30f76E30c160eD06FB 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f 1374 300 \
#   --verify \
#   --via-ir \
#   --private-key ${MUMBAI_PRIVATE_KEY} \
#   --optimize \
#   --optimizer-runs 200 \
#   --chain mumbai \
#   --json \
#  src/DominationGame.sol:DominationGame
