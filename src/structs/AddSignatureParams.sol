// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

struct AddSignatureParams {
    bytes sig;
    uint256 expirationTimestamp;
    address proposer;
    string slug;
    uint256 proposalIdToUpdate;
    bytes encodedProp;
    string reason;
}
