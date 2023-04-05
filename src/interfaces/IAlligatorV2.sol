// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../structs/Rules.sol";

interface IAlligatorV2 {
    // =============================================================
    //                      PROXY OPERATIONS
    // =============================================================

    function create(address owner, Rules calldata proxyRules, bool registerEnsName) external returns (address endpoint);

    function registerProxyDeployment(address owner, Rules calldata proxyRules) external;

    // =============================================================
    //                     GOVERNOR OPERATIONS
    // =============================================================

    function propose(
        Rules calldata proxyRules,
        address[] calldata authority,
        address[] calldata targets,
        uint256[] calldata values,
        string[] calldata signatures,
        bytes[] calldata calldatas,
        string memory description
    ) external returns (uint256 proposalId);

    function castVote(
        Rules calldata proxyRules,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support
    ) external;

    function castVoteWithReason(
        Rules calldata proxyRules,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external;

    function castVotesWithReasonBatched(
        Rules[] calldata proxyRules,
        address[][] calldata authorities,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external;

    function castRefundableVotesWithReasonBatched(
        Rules[] calldata proxyRules,
        address[][] calldata authorities,
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external;

    function castVoteBySig(
        Rules calldata proxyRules,
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function sign(Rules calldata proxyRules, address[] calldata authority, bytes32 hash) external;

    // =============================================================
    //                        SUBDELEGATIONS
    // =============================================================

    function subDelegateAll(address to, Rules calldata subDelegateRules) external;

    function subDelegateAllBatched(address[] calldata targets, Rules[] calldata subDelegateRules) external;

    function subDelegate(
        address proxyOwner,
        Rules calldata proxyRules,
        address to,
        Rules calldata subDelegateRules
    ) external;

    function subDelegateBatched(
        address proxyOwner,
        Rules calldata proxyRules,
        address[] calldata targets,
        Rules[] calldata subDelegateRules
    ) external;

    // =============================================================
    //                          RESTRICTED
    // =============================================================

    function _togglePause() external;

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    function validate(
        Rules memory rules,
        address sender,
        address[] memory authority,
        uint256 permissions,
        uint256 proposalId,
        uint256 support
    ) external view;

    function isValidProxySignature(
        address proxy,
        Rules calldata proxyRules,
        bytes32 hash,
        bytes calldata data
    ) external view returns (bytes4 magicValue);

    function proxyAddress(address owner, Rules calldata proxyRules) external view returns (address endpoint);
}
