// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IGovernorOZExtended} from "src/interfaces/IGovernorOZExtended.sol";
import {IGovernorMock} from "./IGovernorMock.sol";
import "@openzeppelin/contracts/utils/Timers.sol";

contract GovernorOZMock is IGovernorOZExtended, IGovernorMock {
    // =============================================================
    //                            STORAGE
    // =============================================================
    /// @notice Emitted when a voter cast a vote requesting a gas refund.
    event RefundableVote(address indexed voter, uint256 refundAmount, bool refundSent);

    using Timers for Timers.BlockNumber;

    struct ProposalCore {
        Timers.BlockNumber voteStart;
        Timers.BlockNumber voteEnd;
        bool executed;
        bool canceled;
    }

    /// @notice The maximum priority fee used to cap gas refunds in `castRefundableVote`
    uint256 public constant MAX_REFUND_PRIORITY_FEE = 2 gwei;

    /// @notice The vote refund gas overhead, including 7K for ETH transfer and 29K for general transaction overhead
    uint256 public constant REFUND_BASE_GAS = 36000;

    /// @notice The maximum gas units the DAO will refund voters on; supports about 9,190 characters
    uint256 public constant MAX_REFUND_GAS_USED = 200_000;

    /// @notice The maximum basefee the DAO will refund voters on
    uint256 public constant MAX_REFUND_BASE_FEE = 200 gwei;

    address public lastVoter;
    uint256 public lastProposalId;
    uint256 public lastSupport;
    uint256 public totalVotes;
    mapping(address => bool) public _hasVoted;

    mapping(uint256 => ProposalCore) private _proposals;

    constructor() {
        _proposals[1].voteEnd.setDeadline(101);
    }

    // =============================================================
    //                        GOVERNOR STANDARD
    // =============================================================

    function name() public view override returns (string memory) {}

    function version() public view override returns (string memory) {}

    function COUNTING_MODE() public pure override returns (string memory) {}

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure override returns (uint256) {}

    function state(uint256 proposalId) public view override returns (ProposalState) {}

    function proposalSnapshot(uint256 proposalId) public view override returns (uint256) {
        return _proposals[proposalId].voteStart.getDeadline();
    }

    function proposalDeadline(uint256 proposalId) public view override returns (uint256) {
        return _proposals[proposalId].voteEnd.getDeadline();
    }

    function votingDelay() public view override returns (uint256) {}

    function votingPeriod() public view override returns (uint256) {}

    function quorum(uint256 blockNumber) public view override returns (uint256) {}

    function getVotes(address account, uint256 blockNumber) public view override returns (uint256) {}

    function getVotesWithParams(
        address account,
        uint256 blockNumber,
        bytes memory params
    ) public view override returns (uint256) {}

    function hasVoted(address account) external view returns (bool) {
        return _hasVoted[account];
    }

    function hasVoted(uint256, address account) public view override returns (bool) {
        return _hasVoted[account];
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override returns (uint256 proposalId) {}

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable override returns (uint256 proposalId) {}

    function castVote(uint256 proposalId, uint8 support) public override returns (uint256) {
        lastVoter = msg.sender;
        lastProposalId = proposalId;
        lastSupport = support;
        totalVotes += 1;
        _hasVoted[msg.sender] = true;
        emit VoteCast(msg.sender, proposalId, support, 0, "");
        return 0;
    }

    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) public override returns (uint256) {
        require(support <= 2, "castVoteInternal: invalid vote type");
        require(_hasVoted[msg.sender] == false, "castVoteInternal: voter already voted");

        lastVoter = msg.sender;
        lastProposalId = proposalId;
        lastSupport = support;
        totalVotes += 1;
        _hasVoted[msg.sender] = true;
        emit VoteCast(msg.sender, proposalId, support, 0, reason);
        return 0;
    }

    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) public override returns (uint256 balance) {}

    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override returns (uint256 balance) {}

    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override returns (uint256 balance) {}

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }

    // =============================================================
    //                           REFUND LOGIC
    // =============================================================

    function castRefundableVote(uint256 proposalId, uint8 support) external override {}

    function castRefundableVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external override {
        require(support <= 2, "castVoteInternal: invalid vote type");
        require(_hasVoted[msg.sender] == false, "castVoteInternal: voter already voted");
        uint256 startGas = gasleft();

        lastVoter = msg.sender;
        lastProposalId = proposalId;
        lastSupport = support;
        totalVotes += 1;
        _hasVoted[msg.sender] = true;
        emit VoteCast(msg.sender, proposalId, support, 0, reason);

        _refundGas(startGas);
    }

    function _refundGas(uint256 startGas) internal {
        unchecked {
            uint256 balance = address(this).balance;
            if (balance == 0) {
                return;
            }
            uint256 basefee = min(block.basefee, MAX_REFUND_BASE_FEE);
            uint256 gasPrice = min(tx.gasprice, basefee + MAX_REFUND_PRIORITY_FEE);
            uint256 gasUsed = min(startGas - gasleft() + REFUND_BASE_GAS, MAX_REFUND_GAS_USED);
            uint256 refundAmount = min(gasPrice * gasUsed, balance);
            (bool refundSent, ) = tx.origin.call{value: refundAmount}("");
            emit RefundableVote(tx.origin, refundAmount, refundSent);
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
