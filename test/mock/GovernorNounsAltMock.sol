// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {INounsDAOV2} from "src/interfaces/INounsDAOV2.sol";
import {IGovernorMock} from "./IGovernorMock.sol";

// Like `GovernorNounsMock` but which refunds msg.sender instead of tx.origin
contract GovernorNounsAltMock is INounsDAOV2, IGovernorMock {
    /// @notice Emitted when a voter cast a vote requesting a gas refund.
    event RefundableVote(address indexed voter, uint256 refundAmount, bool refundSent);
    event VoteCast(address voter, uint256 proposalId, uint8 support, uint256 votes);

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

    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata) external {
        require(support <= 2, "castVoteInternal: invalid vote type");
        require(hasVoted[msg.sender] == false, "castVoteInternal: voter already voted");

        lastVoter = msg.sender;
        lastProposalId = proposalId;
        lastSupport = support;
        totalVotes += 1;
        hasVoted[msg.sender] = true;
        emit VoteCast(msg.sender, proposalId, support, 0);
    }

    function castVoteBySig(uint256 proposalId, uint8 support, uint8 v, bytes32 r, bytes32 s) external {}

    function proposals(uint256) external view returns (ProposalCondensed memory proposalCondensed) {
        proposalCondensed.endBlock = block.number + 100;
    }

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

    // =============================================================
    //                           REFUND LOGIC
    // =============================================================

    function castRefundableVote(uint256 proposalId, uint8 support) external {}

    function castRefundableVoteWithReason(uint256 proposalId, uint8 support, string calldata) external {
        require(support <= 2, "castVoteInternal: invalid vote type");
        require(hasVoted[msg.sender] == false, "castVoteInternal: voter already voted");
        uint256 startGas = gasleft();

        lastVoter = msg.sender;
        lastProposalId = proposalId;
        lastSupport = support;
        totalVotes += 1;
        hasVoted[msg.sender] = true;
        emit VoteCast(msg.sender, proposalId, support, 0);

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
            (bool refundSent, ) = msg.sender.call{value: refundAmount}("");
            emit RefundableVote(msg.sender, refundAmount, refundSent);
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
