// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {IProxyRegistry} from "noun-contracts/external/opensea/IProxyRegistry.sol";
import {NounsDAOExecutor} from "noun-contracts/governance/NounsDAOExecutor.sol";
import {NounsDAOLogicV2} from "noun-contracts/governance/NounsDAOLogicV2.sol";
import {NounsDAOProxyV2} from "noun-contracts/governance/NounsDAOProxyV2.sol";
import {NounsDescriptor} from "noun-contracts/NounsDescriptor.sol";

contract DeployScript is Script {
    uint256 constant TIMELOCK_DELAY = 2 days;
    uint256 constant VOTING_PERIOD = 5_760; // About 24 hours
    uint256 constant VOTING_DELAY = 1;
    uint256 constant PROPOSAL_THRESHOLD = 1;
    uint256 constant QUORUM_VOTES_BPS = 2000;

    function run() public {
        address noundersDAO = address(0x5);
        address minter = address(0x6);
        IProxyRegistry proxyRegistry = IProxyRegistry(address(0xa5409ec958C83C3f309868babACA7c86DCB077c1));

        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_KEY"));
        vm.startBroadcast(deployer);

        NounsDAOExecutor timelock = new NounsDAOExecutor(address(1), TIMELOCK_DELAY);
        NounsDescriptor descriptor = new NounsDescriptor();
        NounsToken nounsToken = new NounsToken(noundersDAO, minter, descriptor, new NounsSeeder(), proxyRegistry);
        NounsDAOProxy proxy = new NounsDAOProxyV2(
            address(timelock),
            address(nounsToken),
            vetoer,
            address(timelock),
            address(new NounsDAOLogicV2()),
            VOTING_PERIOD,
            VOTING_DELAY,
            PROPOSAL_THRESHOLD,
            QUORUM_VOTES_BPS
        );
    }
}
