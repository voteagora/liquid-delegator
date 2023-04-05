// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

// IGovernor extended with castRefundableVote logic
abstract contract IGovernorOZExtended is IGovernor {
    function castRefundableVote(uint256 proposalId, uint8 support) external virtual;

    function castRefundableVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external virtual;
}
