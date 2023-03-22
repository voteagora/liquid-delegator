// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./IAlligatorV2.sol";

interface IAlligatorV2Open is IAlligatorV2 {
    // =============================================================
    //                     GOVERNOR OPERATIONS
    // =============================================================

    function propose(
        Rules calldata proxyRules,
        address[] calldata authority,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string memory description
    ) external returns (uint256 proposalId);
}
