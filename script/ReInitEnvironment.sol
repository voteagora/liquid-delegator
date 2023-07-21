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

contract ReInitEnvironment is Script {
    address constant nounsToken = 0x05d570185F6e2d29AdaBa1F36435f50Bc44A6f17;
    address constant timelock = 0x3daE99d2Fbc2d625f7C9dE5b602C0a78c35d3320;
    address constant implementation = 0x86CBd869479217cD155102c35462115996a448f0;

    uint256 constant TIMELOCK_DELAY = 2 days;
    uint256 constant VOTING_PERIOD = 40_320; // About 1 week
    uint256 constant VOTING_DELAY = 1;
    uint256 constant PROPOSAL_THRESHOLD = 1;
    uint16 constant QUORUM_VOTES_BPS = 200;

    function run() public returns (NounsDAOProxyV2 proxy) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.rememberKey(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        proxy = new NounsDAOProxyV2(
            timelock,
            nounsToken,
            deployer,
            deployer,
            implementation,
            VOTING_PERIOD,
            VOTING_DELAY,
            PROPOSAL_THRESHOLD,
            NounsDAOStorageV2.DynamicQuorumParams(QUORUM_VOTES_BPS, QUORUM_VOTES_BPS, 0)
        );

        FreeNounsTonken(nounsToken).mint(deployer);
        FreeNounsTonken(nounsToken).mint(deployer);
        FreeNounsTonken(nounsToken).mint(deployer);

        vm.stopBroadcast();
    }
}
