// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {AidraFaucet} from "../src/AidraFaucet.sol";
import {Script,console} from "forge-std/Script.sol";

contract DeployAidraFaucet is Script {
    function run() external {
        vm.startBroadcast();
        AidraFaucet faucet=new AidraFaucet();
        vm.stopBroadcast();
        console.log("Faucet Deployed at:", address(faucet));
    }
}
