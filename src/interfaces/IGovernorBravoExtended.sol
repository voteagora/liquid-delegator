// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IGovernorBravo} from "./IGovernorBravo.sol";

// IGovernorBravo extended with castRefundableVote logic
interface IGovernorBravoExtended is IGovernorBravo {
    // Modified GovernorBravo Proposal struct to account for mapping and arrays being omitted in default mapping getters.
    struct Proposal {
        /// @notice Unique id for looking up a proposal
        uint id;
        /// @notice Creator of the proposal
        address proposer;
        /// @notice The timestamp that the proposal will be available for execution, set once the vote succeeds
        uint eta;
        /// @notice The block at which voting begins: holders must delegate their votes prior to this block
        uint startBlock;
        /// @notice The block at which voting ends: votes must be cast prior to this block
        uint endBlock;
        /// @notice Current number of votes in favor of this proposal
        uint forVotes;
        /// @notice Current number of votes in opposition to this proposal
        uint againstVotes;
        /// @notice Current number of votes for abstaining for this proposal
        uint abstainVotes;
        /// @notice Flag marking whether the proposal has been canceled
        bool canceled;
        /// @notice Flag marking whether the proposal has been executed
        bool executed;
    }

    function proposals(uint256 proposalId) external view returns (Proposal memory);

    function castRefundableVote(uint256 proposalId, uint8 support) external;

    function castRefundableVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external;
}
