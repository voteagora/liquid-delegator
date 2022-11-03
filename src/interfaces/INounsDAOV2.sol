// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IGovernorBravo} from "./IGovernorBravo.sol";

interface INounsDAOV2 is IGovernorBravo {
    function castRefundableVote(uint256 proposalId, uint8 support) external;

    function castRefundableVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external;

    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external;

    function castVoteBySig(uint256 proposalId, uint8 support, uint8 v, bytes32 r, bytes32 s) external;
}
