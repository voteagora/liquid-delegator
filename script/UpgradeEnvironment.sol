// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {NounsSeeder} from "noun-contracts/NounsSeeder.sol";
import {IProxyRegistry} from "noun-contracts/external/opensea/IProxyRegistry.sol";
import {NounsDAOStorageV2} from "noun-contracts/governance/NounsDAOInterfaces.sol";
import {NounsDAOExecutor} from "noun-contracts/governance/NounsDAOExecutor.sol";
import {NounsDAOLogicV2} from "noun-contracts/governance/NounsDAOLogicV2.sol";
import {NounsDAOLogicV3} from "noun-contracts/governance/NounsDAOLogicV3.sol";
import {NounsDAOProxyV2} from "noun-contracts/governance/NounsDAOProxyV2.sol";
import {NounsDAOParams, DynamicQuorumParams} from "noun-contracts/governance/NounsDAOInterfaces.sol";
import {INounsDAOV2} from "../src/interfaces/INounsDAOV2.sol";
import {FreeNounsTonken} from "./FreeNounsToken.sol";

contract InitEnvironment is Script {
    NounsDAOProxyV2 proxy = NounsDAOProxyV2(0x461208f0073e3b1C9Cec568DF2fcACD0700C9B7a);
    address constant nounsToken = 0x05d570185F6e2d29AdaBa1F36435f50Bc44A6f17;
    address constant timelock = 0x3daE99d2Fbc2d625f7C9dE5b602C0a78c35d3320;

    uint256 constant VOTING_PERIOD = 40_320; // About 1 week
    uint256 constant VOTING_DELAY = 1;
    uint256 constant PROPOSAL_THRESHOLD = 1;
    uint16 constant QUORUM_VOTES_BPS = 200;

    function run() public returns (NounsDAOLogicV3 nounsDAOLogicV3) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.rememberKey(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // TODO: figure out correct params
        NounsDAOParams memory daoParams_ = NounsDAOParams({
            votingPeriod: VOTING_PERIOD,
            votingDelay: VOTING_DELAY,
            proposalThresholdBPS: PROPOSAL_THRESHOLD,
            lastMinuteWindowInBlocks: 3600,
            objectionPeriodDurationInBlocks: 360,
            proposalUpdatablePeriodInBlocks: 3600
        });
        DynamicQuorumParams memory dynamicQuorumParams_ = DynamicQuorumParams({
            minQuorumVotesBPS: QUORUM_VOTES_BPS,
            maxQuorumVotesBPS: QUORUM_VOTES_BPS,
            quorumCoefficient: 0
        });

        nounsDAOLogicV3 = new NounsDAOLogicV3();

        proxy._setImplementation(address(nounsDAOLogicV3));

        // nounsDAOLogicV3(proxy).initialize({
        //     timelock_: timelock,
        //     nouns_: nounsToken,
        //     forkEscrow_: address(0),
        //     forkDAODeployer_: address(0),
        //     vetoer_: deployer,
        //     daoParams_: daoParams_,
        //     dynamicQuorumParams_: dynamicQuorumParams_
        // });

        vm.stopBroadcast();
    }
}
