// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IGovernorBravo} from "../src/interfaces/IGovernorBravo.sol";
import "../src/Aligator.sol";
import "./Utils.sol";

contract AligatorTest is Test {
    AligatorOffchainAuthority public aligator;
    NounsDAO public nounsDAO;

    function setUp() public {
        nounsDAO = new NounsDAO();
        aligator = new AligatorOffchainAuthority(IGovernorBravo(address(nounsDAO)));
    }

    function testVote() public {
        address[] memory authority = new address[](0);
        aligator.castVote(authority, 1, 1);
    }

    function testSubDelegate() public {
        address[] memory authority = new address[](1);
        authority[0] = address(Utils.alice);

        aligator.subDelegate(Utils.alice, "1");
        vm.prank(Utils.alice);
        aligator.castVote(authority, 1, 1);
    }

    function testNestedSubDelegate() public {
        address[] memory authority = new address[](3);
        authority[0] = address(Utils.alice);
        authority[1] = address(Utils.bob);
        authority[2] = address(Utils.carol);

        aligator.subDelegate(Utils.alice, "1");
        vm.prank(Utils.alice);
        aligator.subDelegate(Utils.bob, "1");
        vm.prank(Utils.bob);
        aligator.subDelegate(Utils.carol, "1");

        vm.prank(Utils.carol);
        aligator.castVote(authority, 1, 1);
    }

    function testNestedUnDelegate() public {
        address[] memory authority = new address[](3);
        authority[0] = address(Utils.alice);
        authority[1] = address(Utils.bob);
        authority[2] = address(Utils.carol);

        aligator.subDelegate(Utils.alice, "1");
        vm.prank(Utils.alice);
        aligator.subDelegate(Utils.bob, "1");
        vm.prank(Utils.bob);
        aligator.subDelegate(Utils.carol, "1");

        vm.prank(Utils.alice);
        aligator.subDelegate(Utils.bob, "");

        vm.prank(Utils.carol);
        vm.expectRevert();
        aligator.castVote(authority, 1, 1);
    }
}

contract NounsDAO {
    function castVote(uint256 proposalId, uint8 support) external {}
}
