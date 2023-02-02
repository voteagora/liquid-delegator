#!/bin/bash -e

set -o allexport
source .env
set +o allexport

forge script script/DeployNounsAlligator.s.sol -vvvv \
  --gas-price 17000000000 \
  --fork-url https://eth-mainnet.g.alchemy.com/v2/e5W-H540M9FcoGWEzt-KnPd5bzP5zJoh \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY 
  