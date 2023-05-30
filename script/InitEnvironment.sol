// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {NounsSeeder} from "noun-contracts/NounsSeeder.sol";
import {IProxyRegistry} from "noun-contracts/external/opensea/IProxyRegistry.sol";
import {NounsDAOStorageV2} from "noun-contracts/governance/NounsDAOInterfaces.sol";
import {NounsDAOExecutor} from "noun-contracts/governance/NounsDAOExecutor.sol";
import {NounsDAOLogicV2} from "noun-contracts/governance/NounsDAOLogicV2.sol";
import {NounsDAOProxyV2} from "noun-contracts/governance/NounsDAOProxyV2.sol";
import {NounsDescriptor} from "noun-contracts/NounsDescriptor.sol";
import {Alligator} from "../src/v1/Alligator.sol";
import {AlligatorV2Nouns} from "../src/v2/extensions/AlligatorV2Nouns.sol";
import {INounsDAOV2} from "../src/interfaces/INounsDAOV2.sol";
import {ENSNamehash} from "../src/utils/ENSNamehash.sol";
import {FreeNounsTonken} from "./FreeNounsToken.sol";

contract InitEnvironment is Script {
    uint256 constant TIMELOCK_DELAY = 2 days;
    uint256 constant VOTING_PERIOD = 40_320; // About 1 week
    uint256 constant VOTING_DELAY = 1;
    uint256 constant PROPOSAL_THRESHOLD = 1;
    uint16 constant QUORUM_VOTES_BPS = 200;

    function run()
        public
        returns (FreeNounsTonken nounsToken, NounsDAOProxyV2 proxy, Alligator alligatorV1, AlligatorV2Nouns alligatorV2)
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.rememberKey(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy NounsToken
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

        nounsToken = new FreeNounsTonken(deployer, deployer, descriptor, new NounsSeeder(), IProxyRegistry(address(0)));

        // Deploy NounsDAO
        NounsDAOExecutor timelock = new NounsDAOExecutor(address(1), TIMELOCK_DELAY);
        proxy = new NounsDAOProxyV2(
            address(timelock),
            address(nounsToken),
            deployer,
            address(timelock),
            address(new NounsDAOLogicV2()),
            VOTING_PERIOD,
            VOTING_DELAY,
            PROPOSAL_THRESHOLD,
            NounsDAOStorageV2.DynamicQuorumParams(QUORUM_VOTES_BPS, QUORUM_VOTES_BPS, 0)
        );

        nounsToken.mint(deployer);
        nounsToken.mint(deployer);
        nounsToken.mint(deployer);

        // Deploy Alligator
        string memory ensName = "nouns.voteagora.eth";
        bytes32 ensNameHash = ENSNamehash.namehash(bytes(ensName));
        alligatorV1 = new Alligator(INounsDAOV2(address(proxy)), ensName, ensNameHash);
        alligatorV2 = new AlligatorV2Nouns(address(proxy), ensName, ensNameHash, deployer);

        vm.stopBroadcast();
    }
}
