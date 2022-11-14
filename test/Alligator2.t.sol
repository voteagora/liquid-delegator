// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IGovernorBravo} from "../src/interfaces/IGovernorBravo.sol";
import {INounsDAOV2} from "../src/interfaces/INounsDAOV2.sol";
import "../src/Alligator2.sol";
import "./Utils.sol";

contract Alligator2Test is Test {
    Alligator2 public alligator;
    NounsDAO public nounsDAO;
    address public root;

    function setUp() public {
        nounsDAO = new NounsDAO();
        alligator = new Alligator2(nounsDAO);
        root = alligator.create(address(this));
    }

    function testVote() public {
        address[] memory authority = new address[](1);
        authority[0] = root;
        alligator.castVote(authority, 1, 1);
    }

    function testSubDelegate() public {
        address[] memory authority = new address[](2);
        authority[0] = root;
        authority[1] = Utils.alice;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 1,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(root, Utils.alice, rules);
        vm.prank(Utils.alice);
        alligator.castVote(authority, 1, 1);

        assertEq(nounsDAO.lastVoter(), root);
    }

    function testNestedSubDelegate() public {
        address[] memory authority = new address[](4);
        authority[0] = root;
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 1,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(root, Utils.alice, rules);
        vm.prank(Utils.alice);
        alligator.subDelegate(root, Utils.bob, rules);
        vm.prank(Utils.bob);
        alligator.subDelegate(root, Utils.carol, rules);

        vm.prank(Utils.carol);
        alligator.castVote(authority, 1, 1);
    }

    function testNestedUnDelegate() public {
        address[] memory authority = new address[](4);
        authority[0] = root;
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 1,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(root, Utils.alice, rules);
        vm.prank(Utils.alice);
        alligator.subDelegate(root, Utils.bob, rules);
        vm.prank(Utils.bob);
        alligator.subDelegate(root, Utils.carol, rules);

        vm.prank(Utils.alice);
        alligator.subDelegate(
            root,
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
    event VoteCast(address voter, uint256 proposalId, uint8 support, uint256 votes);

    address public lastVoter;
    uint256 public lastProposalId;
    uint256 public lastSupport;

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

    function castVote(uint256 proposalId, uint8 support) external {
        lastVoter = msg.sender;
        lastProposalId = proposalId;
        lastSupport = support;
        emit VoteCast(msg.sender, proposalId, support, 0);
    }

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
