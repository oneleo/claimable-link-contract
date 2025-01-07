source .env

# Deploy the contract to Sepolia network
forge script script/DeployClaimableLink.s.sol --fork-url ${SEPOLIA_NODE_RPC_URL} --broadcast --use 0.8.28 --evm-version shanghai --slow --chain-id 11155111 --etherscan-api-key ${ETHERSCAN_API_KEY} --verify

# If verification fails, it will be re-verified here.
if [ $? -ne 0 ]; then
        contractAddress=$(jq -r '.Sepolia.claimableLink' script/output/ClaimableLink.json)

        forge verify-contract --watch --chain 11155111 --verifier "etherscan" --etherscan-api-key ${ETHERSCAN_API_KEY} --compiler-version 0.8.28 --evm-version shanghai --constructor-args $(cast abi-encode "constructor(address, address[])" ${CLAIMABLE_LINK_ADMIN_ADDRESS} "[${CLAIMABLE_LINK_SIGNER_ADDRESS}]") ${contractAddress} "src/ClaimableLink.sol:ClaimableLink"
fi
