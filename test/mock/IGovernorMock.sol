// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IGovernorMock {
    function hasVoted(address) external view returns (bool);

    function lastVoter() external view returns (address);

    function totalVotes() external view returns (uint256);
}
