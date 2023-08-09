// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {AlligatorSign} from "../src/v1/AlligatorSign.sol";
import {INounsDAOV2} from "../src/interfaces/INounsDAOV2.sol";
import {INounsDAOData} from "../src/interfaces/INounsDAOData.sol";
import {ENSNamehash} from "../src/utils/ENSNamehash.sol";

contract DeployAlligatorSignScript is Script {
    function run() public returns (AlligatorSign alligator) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        INounsDAOV2 nounsDAO = INounsDAOV2(0x35d2670d7C8931AACdd37C89Ddcb0638c3c44A57); // SEPOLIA
        INounsDAOData nounsDAOData = INounsDAOData(0x9040f720AA8A693F950B9cF94764b4b06079D002); // SEPOLIA
        string memory ensName = "nouns.voteagora.eth";
        bytes32 ensNameHash = ENSNamehash.namehash(bytes(ensName));

        alligator = new AlligatorSign(nounsDAO, nounsDAOData, ensName, ensNameHash);

        vm.stopBroadcast();
    }
}
