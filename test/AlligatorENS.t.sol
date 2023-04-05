// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ENS} from "ens-contracts/registry/ENS.sol";
import {ENSNamehash} from "../src/utils/ENSNamehash.sol";
import {INounsDAOV2} from "../src/interfaces/INounsDAOV2.sol";
import {Resolver} from "ens-contracts/resolvers/Resolver.sol";
import "../src/v1/Alligator.sol";
import "../src/v2/extensions/AlligatorV2Nouns.sol";
import "./utils/Addresses.sol";

contract AlligatorENSTest is Test {
    error AlreadyRegistered();

    address immutable ensOwner = 0x63FD9D5c51adB4b41629608385Bb2AD05FC63A20;
    ENS immutable ens = ENS(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);
    Rules public baseRules =
        Rules(
            7, // All permissions
            255, // Max redelegations
            0,
            0,
            0,
            address(0)
        );

    function testENSNameV1() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(MAINNET_RPC_URL, 16651000);

        bytes32 ensNameHash = ENSNamehash.namehash("v1.voteagora.eth");
        Alligator alligator = new Alligator(INounsDAOV2(address(0)), "v1.voteagora.eth", ensNameHash);

        vm.prank(ensOwner);
        ens.setSubnodeOwner(
            ENSNamehash.namehash("voteagora.eth"),
            keccak256(abi.encodePacked("v1")),
            address(alligator)
        );

        address proxy1 = alligator.create(address(this), true);
        assertEq(lookupReverseName(proxy1), "1.v1.voteagora.eth");
        assertEq(lookupAddress("1.v1.voteagora.eth"), proxy1);

        address proxy2 = alligator.create(Utils.alice, false);
        assertEq(lookupReverseName(proxy2), "");

        address proxy3 = alligator.create(ensOwner, true);
        assertEq(lookupReverseName(proxy3), "2.v1.voteagora.eth");
        assertEq(lookupAddress("2.v1.voteagora.eth"), proxy3);

        alligator.registerProxyDeployment(Utils.alice);
        assertEq(lookupReverseName(proxy2), "3.v1.voteagora.eth");
        assertEq(lookupAddress("3.v1.voteagora.eth"), proxy2);

        vm.expectRevert(AlreadyRegistered.selector);
        alligator.registerProxyDeployment(address(this));
    }

    function testENSNameV2() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(MAINNET_RPC_URL, 16651000);

        bytes32 ensNameHash = ENSNamehash.namehash("v2.voteagora.eth");
        AlligatorV2Nouns alligator = new AlligatorV2Nouns(address(0), "v2.voteagora.eth", ensNameHash, address(this));

        vm.prank(ensOwner);
        ens.setSubnodeOwner(
            ENSNamehash.namehash("voteagora.eth"),
            keccak256(abi.encodePacked("v2")),
            address(alligator)
        );

        address proxy1 = alligator.create(address(this), baseRules, true);
        assertEq(lookupReverseName(proxy1), "1.v2.voteagora.eth");
        assertEq(lookupAddress("1.v2.voteagora.eth"), proxy1);

        address proxy2 = alligator.create(Utils.alice, baseRules, false);
        assertEq(lookupReverseName(proxy2), "");

        address proxy3 = alligator.create(ensOwner, baseRules, true);
        assertEq(lookupReverseName(proxy3), "2.v2.voteagora.eth");
        assertEq(lookupAddress("2.v2.voteagora.eth"), proxy3);

        alligator.registerProxyDeployment(Utils.alice, baseRules);
        assertEq(lookupReverseName(proxy2), "3.v2.voteagora.eth");
        assertEq(lookupAddress("3.v2.voteagora.eth"), proxy2);

        vm.expectRevert(AlreadyRegistered.selector);
        alligator.registerProxyDeployment(address(this), baseRules);
    }

    function lookupAddress(string memory name) internal view returns (address) {
        bytes32 node = ENSNamehash.namehash(bytes(name));
        address resolver = ens.resolver(node);
        Resolver ensResolver = Resolver(resolver);
        return ensResolver.addr(node);
    }

    function lookupReverseName(address addr) internal view returns (string memory) {
        IReverseRegistrar ensReverseRegistrar = IReverseRegistrar(0x084b1c3C81545d370f3634392De611CaaBFf8148);
        bytes32 node = ensReverseRegistrar.node(addr);
        return ensReverseRegistrar.defaultResolver().name(node);
    }
}

interface IDefaultResolver {
    function name(bytes32 node) external view returns (string memory);
}

interface IReverseRegistrar {
    function node(address addr) external view returns (bytes32);

    function defaultResolver() external view returns (IDefaultResolver);
}
