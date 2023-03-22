// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Alligator} from "../src/v1/Alligator.sol";
import {INounsDAOV2} from "../src/interfaces/INounsDAOV2.sol";

contract DeployNounsAlligatorScript is Script {
    function run() public {
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));

        vm.startBroadcast(deployer);
        Alligator alligator = new Alligator(INounsDAOV2(0x6f3E6272A167e8AcCb32072d08E0957F9c79223d), "", 0);
        vm.stopBroadcast();

        console.log("Alligator deployed at", address(alligator));
    }
}
