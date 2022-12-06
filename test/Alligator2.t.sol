// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
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

        alligator.subDelegate(Utils.alice, rules);
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

        alligator.subDelegate(Utils.alice, rules);
        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules);
        vm.prank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules);

        vm.prank(Utils.carol);
        alligator.castVote(authority, 1, 1);
    }

    function testSharedSubDelegateTree() public {
        address[] memory authority = new address[](4);
        authority[0] = root;
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        address proxy2 = alligator.create(Utils.bob);
        address[] memory authority2 = new address[](2);
        authority2[0] = proxy2;
        authority2[1] = Utils.carol;

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
        assertEq(nounsDAO.lastVoter(), root);

        vm.prank(Utils.carol);
        alligator.castVote(authority2, 1, 1);
        assertEq(nounsDAO.lastVoter(), proxy2);
    }

    function testCastVoteBatched() public {
        address[] memory authority1 = new address[](4);
        authority1[0] = root;
        authority1[1] = Utils.alice;
        authority1[2] = Utils.bob;
        authority1[3] = Utils.carol;

        address proxy2 = alligator.create(Utils.bob);
        address[] memory authority2 = new address[](2);
        authority2[0] = proxy2;
        authority2[1] = Utils.carol;

        address[][] memory authorities = new address[][](2);
        authorities[0] = authority1;
        authorities[1] = authority2;

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
        alligator.castVotesWithReasonBatched(authorities, 1, 1, "");
        assertEq(nounsDAO.hasVoted(root), true);
        assertEq(nounsDAO.hasVoted(proxy2), true);
        assertEq(nounsDAO.totalVotes(), 2);
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

    function testSupportsSigning() public {
        bytes32 hash1 = keccak256(abi.encodePacked("pass"));
        bytes32 hash2 = keccak256(abi.encodePacked("fail"));

        assertEq(IERC1271(root).isValidSignature(hash2, ""), bytes4(0));

        address[] memory authority = new address[](1);
        authority[0] = root;
        alligator.sign(authority, hash1);

        assertEq(IERC1271(root).isValidSignature(hash1, ""), IERC1271.isValidSignature.selector);
        assertEq(IERC1271(root).isValidSignature(hash2, ""), bytes4(0));
    }

    function testNestedSubDelegateSigning() public {
        bytes32 hash1 = keccak256(abi.encodePacked("pass"));

        address[] memory authority = new address[](4);
        authority[0] = root;
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        Rules memory rules = Rules({
            permissions: 0x02,
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
        alligator.sign(authority, hash1);
        assertEq(IERC1271(root).isValidSignature(hash1, ""), IERC1271.isValidSignature.selector);
    }

    function testNestedUnDelegateSigning() public {
        bytes32 hash1 = keccak256(abi.encodePacked("pass"));

        address[] memory authority = new address[](4);
        authority[0] = root;
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        Rules memory rules = Rules({
            permissions: 0x02,
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
        alligator.sign(authority, hash1);
        assertEq(IERC1271(root).isValidSignature(hash1, ""), bytes4(0));
    }
}

contract NounsDAO is INounsDAOV2 {
    event VoteCast(address voter, uint256 proposalId, uint8 support, uint256 votes);

    address public lastVoter;
    uint256 public lastProposalId;
    uint256 public lastSupport;
    uint256 public totalVotes;
    mapping(address => bool) public hasVoted;

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
        totalVotes += 1;
        hasVoted[msg.sender] = true;
        emit VoteCast(msg.sender, proposalId, support, 0);
    }

    function queue(uint256 proposalId) external {}

    function execute(uint256 proposalId) external {}

    function castRefundableVote(uint256 proposalId, uint8 support) external {}

    function castRefundableVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external {}

    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external {
        lastVoter = msg.sender;
        lastProposalId = proposalId;
        lastSupport = support;
        totalVotes += 1;
        hasVoted[msg.sender] = true;
        emit VoteCast(msg.sender, proposalId, support, 0);
    }

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
