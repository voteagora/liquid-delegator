// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {CREATE3Factory} from "create3-factory/CREATE3Factory.sol";
import {AlligatorV2Nouns} from "../src/v2/extensions/AlligatorV2Nouns.sol";
import {INounsDAOV2} from "../src/interfaces/INounsDAOV2.sol";
import {ENSNamehash} from "../src/utils/ENSNamehash.sol";

contract DeployAlligatorV2Script is Script {
    function run() public returns (AlligatorV2Nouns alligator) {
        CREATE3Factory create3Factory = CREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);
        bytes32 salt = keccak256(bytes(vm.envString("SALT")));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // 0x0699919b235555Be219552912D4a992774e7FB2b
        address initOwner = 0x75a3A0d9e5aa246976e8B5775b224Efb3f9b2f9e;

        vm.startBroadcast(deployerPrivateKey);

        // INounsDAOV2 nounsDAO = INounsDAOV2(0xD08faCeb444dbb6b063a51C2ddFb564Fa0f8Dce0); // GOERLI
        INounsDAOV2 nounsDAO = INounsDAOV2(0x6f3E6272A167e8AcCb32072d08E0957F9c79223d); // MAINNET
        string memory ensName = "nouns.voteagora.eth";
        bytes32 ensNameHash = ENSNamehash.namehash(bytes(ensName));

        alligator = AlligatorV2Nouns(
            payable(
                create3Factory.deploy(
                    salt,
                    bytes.concat(
                        type(AlligatorV2Nouns).creationCode,
                        abi.encode(nounsDAO, ensName, ensNameHash, initOwner)
                    )
                )
            )
        );

        vm.stopBroadcast();
    }
}
