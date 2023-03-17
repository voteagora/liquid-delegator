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
import {INounsDAOV2} from "../src/interfaces/INounsDAOV2.sol";

contract DeployScript is Script {
    uint256 constant TIMELOCK_DELAY = 2 days;
    uint256 constant VOTING_PERIOD = 5_760; // About 24 hours
    uint256 constant VOTING_DELAY = 1;
    uint256 constant PROPOSAL_THRESHOLD = 1;
    uint16 constant QUORUM_VOTES_BPS = 200;

    function run() public {
        // Test wallet: 0x77777101E31b4F3ECafF209704E947855eFbd014
        address deployer = vm.rememberKey(0x98d35887bece258e8e6b407b13c92004d76c2ffe63b4cbbe343839aaca6bdb9f);

        // Give all superpowers to the deployer
        address noundersDAO = deployer;
        address minter = deployer;
        address vetoer = deployer;

        IProxyRegistry proxyRegistry = IProxyRegistry(address(0xa5409ec958C83C3f309868babACA7c86DCB077c1));

        vm.startBroadcast(deployer);

        NounsDAOExecutor timelock = new NounsDAOExecutor(address(1), TIMELOCK_DELAY);
        NounsDescriptor descriptor = new NounsDescriptor();

        {
            string[] memory strs = new string[](1);
            strs[0] = "#fff";
            bytes[] memory bts = new bytes[](1);
            bts[0] = bytes(strs[0]);

            descriptor.addManyBackgrounds(strs);
            descriptor.addManyColorsToPalette(0, strs);
            descriptor.addManyBodies(bts);
            descriptor.addManyAccessories(bts);
            descriptor.addManyHeads(bts);
            descriptor.addManyGlasses(bts);
        }

        FreeNounsTonken nounsToken = new FreeNounsTonken(
            noundersDAO,
            minter,
            descriptor,
            new NounsSeeder(),
            proxyRegistry
        );
        NounsDAOProxyV2 proxy = new NounsDAOProxyV2(
            address(timelock),
            address(nounsToken),
            vetoer,
            address(timelock),
            address(new NounsDAOLogicV2()),
            VOTING_PERIOD,
            VOTING_DELAY,
            PROPOSAL_THRESHOLD,
            NounsDAOStorageV2.DynamicQuorumParams(QUORUM_VOTES_BPS, QUORUM_VOTES_BPS, 0)
        );

        nounsToken.mint(deployer, 1);
        nounsToken.mint(deployer, 2);
        nounsToken.mint(deployer, 3);

        console.log("NounsDAOProxyV2", address(proxy));
    }
}
