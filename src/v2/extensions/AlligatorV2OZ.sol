// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../AlligatorV2.sol";
import {IGovernorOZExtended} from "../../interfaces/IGovernorOZExtended.sol";

contract AlligatorV2OZ is AlligatorV2 {
    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(
        address _governor,
        string memory _ensName,
        bytes32 _ensNameHash,
        address _initOwner
    ) AlligatorV2(_governor, _ensName, _ensNameHash, _initOwner) {}

    // =============================================================
    //                   CUSTOM GOVERNOR FUNCTIONS
    // =============================================================

    /**
     * @notice Make a proposal on the governor.
     *
     * @param proxy The address of the Proxy
     * @param targets Target addresses for proposal calls
     * @param values Eth values for proposal calls
     * @param calldatas Calldatas for proposal calls
     * @param description String description of the proposal
     * @return ID of the created proposal
     */
    function _propose(
        address proxy,
        address[] calldata targets,
        uint256[] calldata values,
        string[] calldata,
        bytes[] calldata calldatas,
        string memory description
    ) internal override returns (uint256) {
        return IGovernorOZExtended(proxy).propose(targets, values, calldatas, description);
    }

    /**
     * @notice Cast a vote on the governor.
     *
     * @param proxy The address of the Proxy
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     */
    function _castVote(address proxy, uint256 proposalId, uint8 support) internal override {
        IGovernorOZExtended(proxy).castVote(proposalId, support);
    }

    /**
     * @notice Cast a vote on the governor with reason.
     *
     * @param proxy The address of the Proxy
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     */
    function _castVoteWithReason(
        address proxy,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) internal override {
        IGovernorOZExtended(proxy).castVoteWithReason(proposalId, support, reason);
    }

    /**
     * @notice Cast a refundable vote on the governor with reason.
     *
     * @param proxy The address of the Proxy
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     */
    function _castRefundableVoteWithReason(
        address proxy,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) internal override {
        IGovernorOZExtended(proxy).castRefundableVoteWithReason(proposalId, support, reason);
    }

    /**
     * @notice Retrieve number of the proposal's end block.
     *
     * @param proposalId The id of the proposal to vote on
     * @return Proposal's end block number.
     */
    function _proposalEndBlock(uint256 proposalId) internal view override returns (uint256) {
        return IGovernorOZExtended(governor).proposalDeadline(proposalId);
    }
}
