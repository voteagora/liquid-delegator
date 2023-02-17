// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IGovernorBravo} from "../src/interfaces/IGovernorBravo.sol";
import {INounsDAOV2} from "../src/interfaces/INounsDAOV2.sol";
import "../src/Alligator.sol";
import "./Utils.sol";
import {ENS} from "ens-contracts/registry/ENS.sol";

contract AlligatorENSTest is Test {
    address immutable w1nt3r = 0x1E79b045Dc29eAe9fdc69673c9DCd7C53E5E159D;

    function testENSName() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(MAINNET_RPC_URL, 16651000);

        bytes32 ensNameHash = 0x4898f9bb4f8f73eed4f7f71ecd16fbe6a0fd0b4ee5fd732b8b225c5f0ea16524;
        Alligator alligator = new Alligator(INounsDAOV2(address(0)), "al.w1nt3r.eth", ensNameHash);

        vm.prank(w1nt3r);
        ENS(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e).setSubnodeOwner(
            0x7c4c4f589b652b90fcb7a27147ab6b3b0674c65e279c60aa9297e8041da23589,
            0x4677be8c780480a69d828bc59996257213298f29b0b05a92f2225875b06d85be,
            address(alligator)
        );

        address proxy1 = alligator.create(address(this));
        assertEq(lookupReverseName(proxy1), "1.al.w1nt3r.eth");

        address proxy2 = alligator.create(w1nt3r);
        assertEq(lookupReverseName(proxy2), "2.al.w1nt3r.eth");
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
