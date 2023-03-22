// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./IAlligatorV2.sol";

interface IAlligatorV2Bravo is IAlligatorV2 {
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
}
