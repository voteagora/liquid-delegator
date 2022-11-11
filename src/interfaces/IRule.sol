// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IRule {
    function validate(address governor, address voter, uint256 proposalId, uint8 support)
        external
        view
        returns (bytes4);
}
