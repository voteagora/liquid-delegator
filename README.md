# Agora Liquid Delegator

Running tests:

1. Install [foundry](https://book.getfoundry.sh/getting-started/installation)
2. `forge test`

Deploying to testnet:

1. Fund `0x77777101E31b4F3ECafF209704E947855eFbd014` with SepoliaETH
2. Get Etherscan API key
3. `forge script script/DeployAlligator.s.sol -vvvv --fork-url https://rpc-sepolia.rockx.com --chain-id 11155111 --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY`
