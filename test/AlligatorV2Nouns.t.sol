// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AlligatorV2Nouns} from "src/v2/extensions/AlligatorV2Nouns.sol";
import "./utils/AlligatorV2Base.sol";
import "./mock/GovernorNounsMock.sol";
import "./mock/GovernorNounsAltMock.sol";

contract AlligatorV2NounsTest is AlligatorV2Base {
    // =============================================================
    //                             TESTS
    // =============================================================

    AlligatorV2 public alligatorAlt;
    GovernorNounsAltMock public governorAlt;
    address public rootAlt;

    function setUp() public override {
        SetupV2.setUp();

        governor = new GovernorNounsMock();
        alligator = AlligatorV2(
            payable(
                _create3Factory.deploy(
                    keccak256(bytes("SALT")),
                    bytes.concat(
                        type(AlligatorV2Nouns).creationCode,
                        abi.encode(address(governor), "", 0, address(this))
                    )
                )
            )
        );
        root = alligator.create(address(this), baseRules, true); // selfProxy

        governorAlt = new GovernorNounsAltMock();
        alligatorAlt = AlligatorV2(
            payable(
                _create3Factory.deploy(
                    keccak256(bytes("SALTALT")),
                    bytes.concat(
                        type(AlligatorV2Nouns).creationCode,
                        abi.encode(address(governorAlt), "", 0, address(this))
                    )
                )
            )
        );
        rootAlt = alligatorAlt.create(address(this), baseRules, true); // selfProxy
    }

    // Run `forge test` with --gas-price param to set the gas price
    function testCastRefundableVotesWithReasonBatched_withMsgSender() public {
        uint256 refundAmount = 206108 * tx.gasprice;
        vm.deal(address(governorAlt), 1 ether);

        address[] memory authority1 = new address[](4);
        authority1[0] = address(this);
        authority1[1] = Utils.alice;
        authority1[2] = Utils.bob;
        authority1[3] = Utils.carol;

        address[] memory authority2 = new address[](2);
        authority2[0] = Utils.bob;
        authority2[1] = Utils.carol;

        address[][] memory authorities = new address[][](2);
        authorities[0] = authority1;
        authorities[1] = authority2;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligatorAlt.subDelegate(address(this), baseRules, Utils.alice, rules);
        vm.prank(Utils.alice);
        alligatorAlt.subDelegate(address(this), baseRules, Utils.bob, rules);
        vm.prank(Utils.bob);
        alligatorAlt.subDelegate(address(this), baseRules, Utils.carol, rules);
        vm.prank(Utils.bob);
        alligatorAlt.subDelegate(Utils.bob, baseRules, Utils.carol, rules);

        Rules[] memory proxyRules = new Rules[](2);
        proxyRules[0] = baseRules;
        proxyRules[1] = baseRules;

        vm.prank(Utils.carol, Utils.carol);
        alligatorAlt.castRefundableVotesWithReasonBatched{gas: 1e9}(proxyRules, authorities, 1, 1, "");

        assertEq(governorAlt.hasVoted(alligatorAlt.proxyAddress(address(this), baseRules)), true);
        assertEq(governorAlt.hasVoted(alligatorAlt.proxyAddress(Utils.bob, baseRules)), true);
        assertEq(governorAlt.totalVotes(), 2);
        assertEq(Utils.carol.balance, refundAmount);
    }

    // Run `forge test` with --gas-price param to set the gas price
    function testCastRefundableVotesWithReasonBatched_mainnetFork() public {
        INounsDAOV2 nounsGovernor = INounsDAOV2(0x6f3E6272A167e8AcCb32072d08E0957F9c79223d);
        DelegateToken nounsToken = DelegateToken(0x9C8fF314C9Bc7F6e59A9d9225Fb22946427eDC03);
        vm.deal(address(nounsGovernor), 1 ether);
        address nounders = 0x2573C60a6D127755aA2DC85e342F7da2378a0Cc5;

        address[] memory authority1 = new address[](4);
        authority1[0] = address(this);
        authority1[1] = Utils.alice;
        authority1[2] = Utils.bob;
        authority1[3] = nounders;

        address[] memory authority2 = new address[](2);
        authority2[0] = Utils.bob;
        authority2[1] = nounders;

        address[][] memory authorities = new address[][](2);
        authorities[0] = authority1;
        authorities[1] = authority2;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        Rules[] memory proxyRules = new Rules[](2);
        proxyRules[0] = baseRules;
        proxyRules[1] = baseRules;

        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        // vm.createSelectFork(MAINNET_RPC_URL, 16770520);
        vm.createSelectFork(MAINNET_RPC_URL, 16770525);

        AlligatorV2 alligatorFork = new AlligatorV2Nouns(address(nounsGovernor), "v2.voteagora.eth", "", address(this));

        // TODO: Reenable when rollFork bug is fixed

        // uint256 refundAmount = 206108 * tx.gasprice;
        // uint256 startBalance = nounders.balance;

        // nounsToken.delegate(alligatorFork.proxyAddress(address(this), baseRules));
        // vm.prank(Utils.bob);
        // nounsToken.delegate(alligatorFork.proxyAddress(Utils.bob, baseRules));

        // vm.rollFork(16770525);

        alligatorFork.subDelegate(address(this), baseRules, Utils.alice, rules);
        vm.prank(Utils.alice);
        alligatorFork.subDelegate(address(this), baseRules, Utils.bob, rules);
        vm.prank(Utils.bob);
        alligatorFork.subDelegate(address(this), baseRules, nounders, rules);
        vm.prank(Utils.bob);
        alligatorFork.subDelegate(Utils.bob, baseRules, nounders, rules);

        vm.prank(nounders);
        nounsToken.transferFrom(nounders, address(this), 580);
        vm.prank(nounders);
        nounsToken.transferFrom(nounders, Utils.bob, 590);

        vm.prank(nounders, nounders);
        alligatorFork.castRefundableVotesWithReasonBatched{gas: 1e9}(proxyRules, authorities, 245, 1, "reason");

        // assertEq(nounders.balance, startBalance + refundAmount);
    }
}
