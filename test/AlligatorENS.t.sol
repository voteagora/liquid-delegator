// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ENS} from "ens-contracts/registry/ENS.sol";
import {ENSNamehash} from "../src/ENSNamehash.sol";
import {INounsDAOV2} from "../src/interfaces/INounsDAOV2.sol";
import {Resolver} from "ens-contracts/resolvers/Resolver.sol";
import "../src/Alligator.sol";
import "./Utils.sol";

contract AlligatorENSTest is Test {
    error AlreadyRegistered();

    address immutable w1nt3r = 0x1E79b045Dc29eAe9fdc69673c9DCd7C53E5E159D;
    ENS immutable ens = ENS(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);

    function testENSName() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(MAINNET_RPC_URL, 16651000);

        bytes32 ensNameHash = ENSNamehash.namehash("al.w1nt3r.eth");
        Alligator alligator = new Alligator(INounsDAOV2(address(0)), "al.w1nt3r.eth", ensNameHash);

        vm.prank(w1nt3r);
        ens.setSubnodeOwner(ENSNamehash.namehash("w1nt3r.eth"), keccak256(abi.encodePacked("al")), address(alligator));

        address proxy1 = alligator.create(address(this), true);
        assertEq(lookupReverseName(proxy1), "1.al.w1nt3r.eth");
        assertEq(lookupAddress("1.al.w1nt3r.eth"), proxy1);

        address proxy2 = alligator.create(Utils.alice, false);
        assertEq(lookupReverseName(proxy2), "");

        address proxy3 = alligator.create(w1nt3r, true);
        assertEq(lookupReverseName(proxy3), "2.al.w1nt3r.eth");
        assertEq(lookupAddress("2.al.w1nt3r.eth"), proxy3);

        alligator.registerProxyDeployment(Utils.alice);
        assertEq(lookupReverseName(proxy2), "3.al.w1nt3r.eth");
        assertEq(lookupAddress("3.al.w1nt3r.eth"), proxy2);

        vm.expectRevert(AlreadyRegistered.selector);
        alligator.registerProxyDeployment(address(this));
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
