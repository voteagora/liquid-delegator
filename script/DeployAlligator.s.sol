// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Alligator} from "../src/v1/Alligator.sol";
import {INounsDAOV2} from "../src/interfaces/INounsDAOV2.sol";
import {ENSNamehash} from "../src/utils/ENSNamehash.sol";

contract DeployAlligatorScript is Script {
    function run() public returns (Alligator alligator) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // 0x0699919b235555Be219552912D4a992774e7FB2b
        address owner = 0x75a3A0d9e5aa246976e8B5775b224Efb3f9b2f9e;

        vm.startBroadcast(deployerPrivateKey);

        // INounsDAOV2 nounsDAO = INounsDAOV2(0xD08faCeb444dbb6b063a51C2ddFb564Fa0f8Dce0); // GOERLI
        INounsDAOV2 nounsDAO = INounsDAOV2(0x6f3E6272A167e8AcCb32072d08E0957F9c79223d); // MAINNET
        string memory ensName = "nouns.voteagora.eth";
        bytes32 ensNameHash = ENSNamehash.namehash(bytes(ensName));

        alligator = new Alligator(nounsDAO, ensName, ensNameHash);

        if (owner != address(0)) {
            alligator.transferOwnership(owner);
        }

        vm.stopBroadcast();
    }
}
