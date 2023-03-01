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

contract DeployAlligatorScript is Script {
    function run() public {
        // Test wallet: 0x77777101E31b4F3ECafF209704E947855eFbd014
        address deployer = vm.rememberKey(0x98d35887bece258e8e6b407b13c92004d76c2ffe63b4cbbe343839aaca6bdb9f);
        vm.startBroadcast(deployer);

        FreeNounsTonken nounsToken = FreeNounsTonken(address(0x391de1cEa53bD058fFf3216F36a3009D34cFa8D9));
        address nounsDAO = 0x8044715f20bE17CE0F92535c2968789e3B19CC09;

        Alligator alligator = new Alligator(INounsDAOV2(nounsDAO), "", 0);
        address proxy = alligator.create(deployer);
        nounsToken.delegate(proxy);

        alligator.subDelegate(
            0xC3FdAdbAe46798CD8762185A09C5b672A7aA36Bb,
            Rules({
                permissions: 0x07,
                maxRedelegations: 0,
                notValidBefore: 0,
                notValidAfter: 0,
                blocksBeforeVoteCloses: 0,
                customRule: address(0)
            })
        );
        alligator.subDelegate(
            0x1E79b045Dc29eAe9fdc69673c9DCd7C53E5E159D,
            Rules({
                permissions: 0x07,
                maxRedelegations: 0,
                notValidBefore: 0,
                notValidAfter: 0,
                blocksBeforeVoteCloses: 0,
                customRule: address(0)
            })
        );
    }
}
