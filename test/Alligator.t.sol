// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IGovernorBravo} from "../src/interfaces/IGovernorBravo.sol";
import {INounsDAOV2} from "../src/interfaces/INounsDAOV2.sol";
import "../src/Alligator.sol";
import "./Utils.sol";

contract AlligatorTest is Test {
    AlligatorFactory public factory;
    AlligatorWithRules public alligator;
    NounsDAO public nounsDAO;

    function setUp() public {
        nounsDAO = new NounsDAO();
        factory = new AlligatorFactory(nounsDAO);
        alligator = factory.create(address(this));
    }

    function testVote() public {
        address[] memory authority = new address[](0);
        alligator.castVote(authority, 1, 1);
    }

    function testSubDelegate() public {
        address[] memory authority = new address[](1);
        authority[0] = address(Utils.alice);

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 1,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(Utils.alice, rules);
        vm.prank(Utils.alice);
        alligator.castVote(authority, 1, 1);
    }

    function testNestedSubDelegate() public {
        address[] memory authority = new address[](3);
        authority[0] = address(Utils.alice);
        authority[1] = address(Utils.bob);
        authority[2] = address(Utils.carol);

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 1,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(Utils.alice, rules);
        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules);
        vm.prank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules);

        vm.prank(Utils.carol);
        alligator.castVote(authority, 1, 1);
    }

    function testNestedUnDelegate() public {
        address[] memory authority = new address[](3);
        authority[0] = address(Utils.alice);
        authority[1] = address(Utils.bob);
        authority[2] = address(Utils.carol);

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 1,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(Utils.alice, rules);
        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules);
        vm.prank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules);

        vm.prank(Utils.alice);
        alligator.subDelegate(
            Utils.bob,
            Rules({
                permissions: 0,
                maxRedelegations: 0,
                notValidBefore: 0,
                notValidAfter: 0,
                blocksBeforeVoteCloses: 0,
                customRule: address(0)
            })
        );

        vm.prank(Utils.carol);
        vm.expectRevert();
        alligator.castVote(authority, 1, 1);
    }
}

contract NounsDAO is INounsDAOV2 {
    function quorumVotes() external view returns (uint256) {}

    function votingDelay() external view returns (uint256) {}

    function votingPeriod() external view returns (uint256) {}

    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256) {}

    function castVote(uint256 proposalId, uint8 support) external {}

    function queue(uint256 proposalId) external {}

    function execute(uint256 proposalId) external {}

    function castRefundableVote(uint256 proposalId, uint8 support) external {}

    function castRefundableVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external {}

    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external {}

    function castVoteBySig(uint256 proposalId, uint8 support, uint8 v, bytes32 r, bytes32 s) external {}

    function proposals(uint256 proposalId) external view returns (ProposalCondensed memory) {}

    function getActions(uint256 proposalId)
        external
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        )
    {}
}
