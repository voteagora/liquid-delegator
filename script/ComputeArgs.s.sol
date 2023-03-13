// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {ENSNamehash} from "../src/utils/ENSNamehash.sol";

contract ComputeArgsScript is Script {
    function run() public pure returns (bytes32 namehash, bytes32 subdomainHash) {
        namehash = ENSNamehash.namehash("voteagora.eth");
        subdomainHash = keccak256(abi.encodePacked("nouns"));
    }
}
