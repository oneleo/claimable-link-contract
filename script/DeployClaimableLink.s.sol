// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Network} from "test/util/Network.sol";

import {ClaimableLink} from "src/ClaimableLink.sol";

contract ClaimableLinkDeploy is Script {
    ClaimableLink claimableLink;

    address deployer = vm.rememberKey(vm.envUint("DEPLOYER_PRIVATE_KEY"));
    address admin = vm.envAddress("CLAIMABLE_LINK_ADMIN_ADDRESS");
    address signer = vm.envAddress("CLAIMABLE_LINK_SIGNER_ADDRESS");

    function run() external {
        address[] memory signers = new address[](1);
        signers[0] = signer;

        vm.startBroadcast(deployer);
        claimableLink = new ClaimableLink{
            salt: keccak256(abi.encode("ClaimableLink"))
        }(admin, signers);
        vm.stopBroadcast();

        string memory currentNetwork = Network.getNetworkName(block.chainid);
        string memory jsonData = vm.toString(address(claimableLink));
        string memory outputFilePath = string.concat(
            "script/output/ClaimableLink.json"
        );
        string memory jsonPath = string.concat(
            ".",
            currentNetwork,
            ".claimableLink"
        );

        vm.writeJson(jsonData, outputFilePath, jsonPath);

        console.log("claimableLink:");
        console.logAddress(address(claimableLink));
    }
}
