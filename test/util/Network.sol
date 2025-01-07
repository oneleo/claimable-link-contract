// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

library Network {
    uint256 constant Local = 31337;
    uint256 constant Mainnet = 1;
    uint256 constant Optimism = 10;
    uint256 constant Polygon = 137;
    uint256 constant Holesky = 17000;
    uint256 constant Mumbai = 80001;
    uint256 constant Amoy = 80002;
    uint256 constant Arbitrum_Sepolia = 421614;
    uint256 constant Sepolia = 11155111;
    uint256 constant Optimism_Sepolia = 11155420;
    uint256 constant Base_Sepolia = 84532;

    function getNetworkName(uint256 chainId) internal pure returns (string memory network) {
        if (chainId == Local) {
            network = "Local";
        } else if (chainId == Mainnet) {
            network = "Mainnet";
        } else if (chainId == Optimism) {
            network = "Optimism";
        } else if (chainId == Polygon) {
            network = "Polygon";
        } else if (chainId == Holesky) {
            network = "Holesky";
        } else if (chainId == Mumbai) {
            network = "Mumbai";
        } else if (chainId == Amoy) {
            network = "Amoy";
        } else if (chainId == Arbitrum_Sepolia) {
            network = "Arbitrum_Sepolia";
        } else if (chainId == Sepolia) {
            network = "Sepolia";
        } else if (chainId == Optimism_Sepolia) {
            network = "Optimism_Sepolia";
        } else if (chainId == Base_Sepolia) {
            network = "Base_Sepolia";
        } else {
            revert("unsupported chain id");
        }
    }
}
