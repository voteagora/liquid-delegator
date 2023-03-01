// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {IProxyRegistry} from "noun-contracts/external/opensea/IProxyRegistry.sol";
import {NounsDAOExecutor} from "noun-contracts/governance/NounsDAOExecutor.sol";
import {NounsDAOLogicV2} from "noun-contracts/governance/NounsDAOLogicV2.sol";
import {NounsDAOProxyV2} from "noun-contracts/governance/NounsDAOProxyV2.sol";
import {NounsDAOStorageV2} from "noun-contracts/governance/NounsDAOInterfaces.sol";
import {NounsDescriptor} from "noun-contracts/NounsDescriptor.sol";
import {NounsToken} from "noun-contracts/NounsToken.sol";
import {NounsSeeder} from "noun-contracts/NounsSeeder.sol";

contract FreeNounsTonken is NounsToken {
    constructor(
        address noundersDAO,
        address minter,
        NounsDescriptor descriptor,
        NounsSeeder seeder,
        IProxyRegistry proxyRegistry
    ) NounsToken(noundersDAO, minter, descriptor, seeder, proxyRegistry) {}

    function mint(address to, uint256 tokenId) public {
        _mintTo(to, tokenId);
    }
}
