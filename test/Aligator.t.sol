// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IGovernorBravo} from "../src/interfaces/IGovernorBravo.sol";
import "../src/Aligator.sol";
import "./Utils.sol";

contract AligatorTest is Test {
    AligatorOnchainAuthority public aligator;
    NounsDAO public nounsDAO;

    function setUp() public {
        nounsDAO = new NounsDAO();
        aligator = new AligatorOnchainAuthority(IGovernorBravo(address(nounsDAO)));
    }

    function testVote() public {
        aligator.castVote(1, 1);
    }

    function testSubDelegate() public {
        aligator.subDelegate(Utils.alice, true);
        vm.prank(Utils.alice);
        aligator.castVote(1, 1);
    }

    function testNestedSubDelegate() public {
        aligator.subDelegate(Utils.alice, true);
        vm.prank(Utils.alice);
        aligator.subDelegate(Utils.bob, true);
        vm.prank(Utils.bob);
        aligator.subDelegate(Utils.carol, true);

        vm.prank(Utils.carol);
        aligator.castVote(1, 1);
    }

    function testNestedUnDelegate() public {
        aligator.subDelegate(Utils.alice, true);
        vm.prank(Utils.alice);
        aligator.subDelegate(Utils.bob, true);
        vm.prank(Utils.bob);
        aligator.subDelegate(Utils.carol, true);

        vm.prank(Utils.alice);
        aligator.subDelegate(Utils.bob, false);

        vm.prank(Utils.carol);
        vm.expectRevert();
        aligator.castVote(1, 1);
    }
}

contract NounsDAO {
    function castVote(uint256 proposalId, uint8 support) external {}
}
