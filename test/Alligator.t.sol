// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IGovernorBravo} from "../src/interfaces/IGovernorBravo.sol";
import {INounsDAOV2} from "../src/interfaces/INounsDAOV2.sol";
import "../src/Alligator.sol";
import "./Utils.sol";

contract AlligatorTest is Test {
    // =============================================================
    //                  ERRORS & EVENTS & CONSTANTS
    // =============================================================

    error BadSignature();
    error NotDelegated(address from, address to, uint8 requiredPermissions);
    error TooManyRedelegations(address from, address to);
    error NotValidYet(address from, address to, uint32 willBeValidFrom);
    error NotValidAnymore(address from, address to, uint32 wasValidUntil);
    error TooEarly(address from, address to, uint32 blocksBeforeVoteCloses);
    error InvalidCustomRule(address from, address to, address customRule);

    event ProxyDeployed(address indexed owner, address proxy);
    event SubDelegation(address indexed from, address indexed to, Rules rules);
    event SubDelegations(address indexed from, address[] to, Rules[] rules);
    event VoteCast(
        address indexed proxy,
        address indexed voter,
        address[] authority,
        uint256 proposalId,
        uint8 support
    );
    event VotesCast(
        address[] proxies,
        address indexed voter,
        address[][] authorities,
        uint256 proposalId,
        uint8 support
    );
    event Signed(address indexed proxy, address[] authority, bytes32 messageHash);
    event RefundableVote(address indexed voter, uint256 refundAmount, bool refundSent);

    uint8 internal constant PERMISSION_VOTE = 1;
    uint8 internal constant PERMISSION_SIGN = 1 << 1;
    uint8 internal constant PERMISSION_PROPOSE = 1 << 2;

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    bytes32 internal constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    /// @notice The maximum priority fee used to cap gas refunds in `castRefundableVote`
    uint256 public constant MAX_REFUND_PRIORITY_FEE = 2 gwei;

    /// @notice The vote refund gas overhead, including 7K for ETH transfer and 29K for general transaction overhead
    uint256 public constant REFUND_BASE_GAS = 36000;

    /// @notice The maximum gas units the DAO will refund voters on; supports about 9,190 characters
    uint256 public constant MAX_REFUND_GAS_USED = 200_000;

    /// @notice The maximum basefee the DAO will refund voters on
    uint256 public constant MAX_REFUND_BASE_FEE = 200 gwei;

    // =============================================================
    //                             TESTS
    // =============================================================

    Alligator public alligator;
    NounsDAO public nounsDAO;
    address public root;

    function setUp() public {
        nounsDAO = new NounsDAO();
        alligator = new Alligator(nounsDAO, "", 0);
        root = alligator.create(address(this));
    }

    function testProxyAddressMatches() public {
        address proxy = alligator.create(Utils.alice);
        assertEq(alligator.proxyAddress(Utils.alice), proxy);
    }

    function testCastVote() public {
        address[] memory authority = new address[](1);
        authority[0] = address(this);

        vm.expectEmit(true, true, false, true);
        emit VoteCast(alligator.proxyAddress(address(this)), address(this), authority, 1, 1);
        alligator.castVote(authority, 1, 1);
    }

    function testCastVoteWithReason() public {
        address[] memory authority = new address[](1);
        authority[0] = address(this);

        vm.expectEmit(true, true, false, true);
        emit VoteCast(alligator.proxyAddress(address(this)), address(this), authority, 1, 1);
        alligator.castVoteWithReason(authority, 1, 1, "reason");
    }

    function testCastVotesWithReasonBatched() public {
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

        alligator.subDelegate(Utils.alice, rules, true);
        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules, true);
        vm.prank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules, true);

        address[] memory proxies = new address[](2);
        proxies[0] = alligator.proxyAddress(address(this));
        proxies[1] = alligator.proxyAddress(Utils.bob);

        vm.prank(Utils.carol);
        vm.expectEmit(true, true, false, true);
        emit VotesCast(proxies, Utils.carol, authorities, 1, 1);
        alligator.castVotesWithReasonBatched(authorities, 1, 1, "");

        assertEq(nounsDAO.hasVoted(alligator.proxyAddress(address(this))), true);
        assertEq(nounsDAO.hasVoted(alligator.proxyAddress(Utils.bob)), true);
        assertEq(nounsDAO.totalVotes(), 2);
    }

    function testCastVotesWithReasonBatched_withoutProxyCreate() public {
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

        alligator.subDelegate(Utils.alice, rules, false);
        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules, false);
        vm.prank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules, true);

        address[] memory proxies = new address[](2);
        proxies[0] = alligator.proxyAddress(address(this));
        proxies[1] = alligator.proxyAddress(Utils.bob);

        vm.prank(Utils.carol);
        vm.expectEmit(true, true, false, true);
        emit VotesCast(proxies, Utils.carol, authorities, 1, 1);
        alligator.castVotesWithReasonBatched(authorities, 1, 1, "");

        assertTrue(alligator.proxyAddress(Utils.alice).code.length == 0);
        assertEq(nounsDAO.hasVoted(alligator.proxyAddress(address(this))), true);
        assertEq(nounsDAO.hasVoted(alligator.proxyAddress(Utils.bob)), true);
        assertEq(nounsDAO.totalVotes(), 2);
    }

    function testCastRefundableVotesWithReasonBatched() public {
        uint256 initBalance = 1 ether;
        payable(address(alligator)).transfer(initBalance);

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

        alligator.subDelegate(Utils.alice, rules, true);
        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules, true);
        vm.prank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules, true);

        address[] memory proxies = new address[](2);
        proxies[0] = alligator.proxyAddress(address(this));
        proxies[1] = alligator.proxyAddress(Utils.bob);

        vm.prank(Utils.carol);
        vm.expectEmit(true, false, false, true);
        uint256 refundAmount = 200000 * tx.gasprice;
        emit RefundableVote(Utils.carol, refundAmount, true);
        alligator.castRefundableVotesWithReasonBatched{gas: 1e9}(authorities, 1, 1, "");

        assertTrue(alligator.proxyAddress(Utils.alice).code.length != 0);
        assertEq(nounsDAO.hasVoted(alligator.proxyAddress(address(this))), true);
        assertEq(nounsDAO.hasVoted(alligator.proxyAddress(Utils.bob)), true);
        assertEq(nounsDAO.totalVotes(), 2);
        assertEq(address(alligator).balance, initBalance - refundAmount);
    }

    function testSubDelegate_withProxyCreate() public {
        address[] memory authority = new address[](2);
        authority[0] = address(this);
        authority[1] = Utils.alice;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(Utils.alice, rules, true);
        vm.prank(Utils.alice);
        alligator.castVote(authority, 1, 1);
        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules, true);

        assertTrue(alligator.proxyAddress(Utils.alice).code.length != 0);
        assertEq(nounsDAO.lastVoter(), root);
    }

    function testSubDelegate_withoutProxyCreate() public {
        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules, false);
        assertTrue(alligator.proxyAddress(Utils.alice).code.length == 0);
    }

    function testSubDelegateBatched() public {
        address[] memory targets = new address[](2);
        targets[0] = Utils.bob;
        targets[1] = Utils.carol;

        Rules[] memory rules = new Rules[](2);
        rules[0] = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });
        rules[1] = Rules({
            permissions: 0x02,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        vm.prank(Utils.alice);
        alligator.subDelegateBatched(targets, rules, true);

        address aliceProxy = alligator.proxyAddress(Utils.alice);
        assertGt(aliceProxy.code.length, 0);

        (uint8 bobPermissions, , , , , ) = alligator.subDelegations(Utils.alice, Utils.bob);
        assertEq(bobPermissions, 0x01);

        (uint8 carolPermissions, , , , , ) = alligator.subDelegations(Utils.alice, Utils.carol);
        assertEq(carolPermissions, 0x02);
    }

    function testNestedSubDelegate() public {
        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(Utils.alice, rules, true);
        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules, true);
        vm.prank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules, true);

        vm.prank(Utils.carol);
        alligator.castVote(authority, 1, 1);
    }

    function testSharedSubDelegateTree() public {
        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        address proxy2 = alligator.create(Utils.bob);
        address[] memory authority2 = new address[](2);
        authority2[0] = Utils.bob;
        authority2[1] = Utils.carol;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(Utils.alice, rules, true);
        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules, true);
        vm.prank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules, true);

        vm.prank(Utils.carol);
        alligator.castVote(authority, 1, 1);
        assertEq(nounsDAO.lastVoter(), root);

        vm.prank(Utils.carol);
        alligator.castVote(authority2, 1, 1);
        assertEq(nounsDAO.lastVoter(), proxy2);
    }

    function testNestedUnDelegate() public {
        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(Utils.alice, rules, true);
        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules, true);
        vm.prank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules, true);

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
            }),
            true
        );

        vm.prank(Utils.carol);
        vm.expectRevert();
        alligator.castVote(authority, 1, 1);
    }

    function testMaxRedelegations() public {
        address[] memory authority = new address[](4);
        authority[0] = address(this);
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

        alligator.subDelegate(Utils.alice, rules, true);
        vm.prank(Utils.alice);

        rules.maxRedelegations = 255;

        alligator.subDelegate(Utils.bob, rules, true);
        vm.prank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules, true);

        vm.prank(Utils.carol);
        vm.expectRevert();
        alligator.castVote(authority, 1, 1);

        address[] memory authority2 = new address[](3);
        authority2[0] = address(this);
        authority2[1] = Utils.alice;
        authority2[2] = Utils.bob;

        vm.prank(Utils.bob);
        alligator.castVote(authority2, 1, 1);
    }

    function testSupportsSigning() public {
        bytes32 hash1 = keccak256(abi.encodePacked("pass"));
        bytes32 hash2 = keccak256(abi.encodePacked("fail"));

        assertEq(IERC1271(root).isValidSignature(hash2, ""), bytes4(0));

        address[] memory authority = new address[](1);
        authority[0] = address(this);
        alligator.sign(authority, hash1);

        assertEq(IERC1271(root).isValidSignature(hash1, ""), IERC1271.isValidSignature.selector);
        assertEq(IERC1271(root).isValidSignature(hash2, ""), bytes4(0));
    }

    function testNestedSubDelegateSigning() public {
        bytes32 hash1 = keccak256(abi.encodePacked("pass"));

        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        Rules memory rules = Rules({
            permissions: 0x02,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(Utils.alice, rules, true);
        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules, true);
        vm.prank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules, true);

        vm.prank(Utils.carol);
        alligator.sign(authority, hash1);
        assertEq(IERC1271(root).isValidSignature(hash1, ""), IERC1271.isValidSignature.selector);
    }

    function testNestedUnDelegateSigning() public {
        bytes32 hash1 = keccak256(abi.encodePacked("pass"));

        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        Rules memory rules = Rules({
            permissions: 0x02,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(Utils.alice, rules, true);
        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules, true);
        vm.prank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules, true);

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
            }),
            true
        );

        vm.prank(Utils.carol);
        vm.expectRevert();
        alligator.sign(authority, hash1);
        assertEq(IERC1271(root).isValidSignature(hash1, ""), bytes4(0));
    }

    function testOffchainSignatures() public {
        uint256 privateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        address signer = vm.addr(privateKey);
        bytes32 hash1 = keccak256(abi.encodePacked("data"));
        bytes32 hash2 = keccak256(abi.encodePacked("fake"));

        address[] memory authority = new address[](5);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;
        authority[4] = signer;

        Rules memory rules = Rules({
            permissions: 0x02,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(Utils.alice, rules, true);
        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules, true);
        vm.prank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules, true);
        vm.prank(Utils.carol);
        alligator.subDelegate(signer, rules, true);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash1);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory data = abi.encode(authority, signature);

        assertEq(IERC1271(root).isValidSignature(hash1, data), IERC1271.isValidSignature.selector);

        // Different hash means erecover returns a different user
        vm.expectRevert();
        IERC1271(root).isValidSignature(hash2, data);
    }

    // =============================================================
    //                          REVERT TESTS
    // =============================================================

    function testRevert_castVote_validateCheck() public {
        address[] memory authority = new address[](1);
        authority[0] = address(this);
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(NotDelegated.selector, address(this), address(1), PERMISSION_VOTE));
        alligator.castVote(authority, 1, 1);
    }

    function testRevert_castVoteWithReason_validateCheck() public {
        address[] memory authority = new address[](1);
        authority[0] = address(this);
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(NotDelegated.selector, address(this), address(1), PERMISSION_VOTE));
        alligator.castVoteWithReason(authority, 1, 1, "reason");
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

    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata) external {
        lastVoter = msg.sender;
        lastProposalId = proposalId;
        lastSupport = support;
        totalVotes += 1;
        hasVoted[msg.sender] = true;
        emit VoteCast(msg.sender, proposalId, support, 0);
    }

    function castVoteBySig(uint256 proposalId, uint8 support, uint8 v, bytes32 r, bytes32 s) external {}

    function proposals(uint256 proposalId) external view returns (ProposalCondensed memory) {}

    function getActions(
        uint256 proposalId
    )
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
