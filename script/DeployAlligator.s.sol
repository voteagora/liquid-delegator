// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {IProxyRegistry} from "noun-contracts/external/opensea/IProxyRegistry.sol";
import {NounsDAOExecutor} from "noun-contracts/governance/NounsDAOExecutor.sol";
import {NounsDAOLogicV2} from "noun-contracts/governance/NounsDAOLogicV2.sol";
import {NounsDAOProxyV2} from "noun-contracts/governance/NounsDAOProxyV2.sol";
import {NounsDAOStorageV2} from "noun-contracts/governance/NounsDAOInterfaces.sol";
import {NounsDescriptor} from "noun-contracts/NounsDescriptor.sol";
import {FreeNounsTonken} from "./FreeNounsToken.sol";
import {NounsSeeder} from "noun-contracts/NounsSeeder.sol";
import {Alligator, Rules} from "../src/Alligator.sol";
import {INounsDAOV2} from "../src/interfaces/INounsDAOV2.sol";
import {DescriptorImageData} from "./DescriptorImageData.sol";
import {ENSNamehash} from "../src/ENSNamehash.sol";

contract DeployAlligatorScript is Script {
    function run() public returns (Alligator alligator) {
        bytes32 salt = keccak256(bytes(vm.envString("SALT")));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // INounsDAOV2 nounsDAO = INounsDAOV2(0xD08faCeb444dbb6b063a51C2ddFb564Fa0f8Dce0); // GOERLI
        INounsDAOV2 nounsDAO = INounsDAOV2(0x6f3E6272A167e8AcCb32072d08E0957F9c79223d); // MAINNET
        string memory ensName = "nounsagora.eth";
        bytes32 ensNameHash = ENSNamehash.namehash(bytes(ensName));

        alligator = new Alligator{salt: salt}(nounsDAO, ensName, ensNameHash);

        // TODO: Add admin pausable for critical ops?

        vm.stopBroadcast();
    }
}
