// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { Alligator, Rules } from "../src/Alligator.sol";
import { NounsDAOSample } from "./sample/NounsDaoSample.sol";
import { Utils } from "./Utils.sol";

contract Alligator2Test is Test {
    /* -------------------------------------------------------------------------- */
    /*                                   states                                   */
    /* -------------------------------------------------------------------------- */
    Alligator public alligator;
    NounsDAOSample public nounsDAOSample;

    /* -------------------------------------------------------------------------- */
    /*                                    setup                                   */
    /* -------------------------------------------------------------------------- */
    function setUp() public {
        nounsDAOSample = new NounsDAOSample();
        alligator = new Alligator(nounsDAOSample, "", 0);
    }

    /* -------------------------------------------------------------------------- */
    /*                                proxy address                               */
    /* -------------------------------------------------------------------------- */
    function testCreate() public {

        // check proxy
        address proxyAddr = alligator.proxyAddress(Utils.alice);
        assertEq(proxyAddr.code.length, 0);

        // create
        address proxy = alligator.create(Utils.alice);

        // check proxy
        proxyAddr = alligator.proxyAddress(Utils.alice);
        assertGt(proxyAddr.code.length, 0);

        // check proxy addresses match
        assertEq(alligator.proxyAddress(Utils.alice), proxy);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 subdelegate                                */
    /* -------------------------------------------------------------------------- */
    // subdelegate
    function testSubdelegate() public {
        // check permissions
        (uint8 alicePermissions,,,,,) = alligator.subDelegations(address(this), Utils.alice);
        assertEq(alicePermissions, 0);

        // subdelegate
        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(Utils.alice, rules);

        // check permissions
        (alicePermissions,,,,,) = alligator.subDelegations(address(this), Utils.alice);
        assertEq(alicePermissions, 0x01);
    }

    // subdelegate batched
    function testSubdelegateBatched() public {
        // check subdelegatiosn
        (uint8 bobPermissions,,,,,) = alligator.subDelegations(Utils.alice, Utils.bob);
        assertEq(bobPermissions, 0);

        (uint8 carolPermissions,,,,,) = alligator.subDelegations(Utils.alice, Utils.carol);
        assertEq(carolPermissions, 0);

        // subdelegate batched
        address[] memory targets = new address[](2);
        targets[0] = Utils.bob;
        targets[1] = Utils.carol;

        Rules[] memory rules = new Rules[](2);
        rules[0] = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });
        rules[1] = Rules({
            permissions: 0x02,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        vm.startPrank(Utils.alice);
        alligator.subDelegateBatched(targets, rules);
        vm.stopPrank();

        // check subdelegatiosn
        (bobPermissions,,,,,) = alligator.subDelegations(Utils.alice, Utils.bob);
        assertEq(bobPermissions, 0x01);

        (carolPermissions,,,,,) = alligator.subDelegations(Utils.alice, Utils.carol);
        assertEq(carolPermissions, 0x02);
    }
    
    /* -------------------------------------------------------------------------- */
    /*                                    vote                                    */
    /* -------------------------------------------------------------------------- */
    // self proxy
    function testVote_selfProxy() public {
        // create proxy
        address proxy = alligator.create(address(this));

        // check vote
        assertEq(nounsDAOSample.hasVoted(proxy), false);
        assertEq(nounsDAOSample.totalVotes(), 0);
        assertEq(nounsDAOSample.lastVoter(), address(0));

        // vote
        address[] memory authority = new address[](1);
        authority[0] = address(this);
        alligator.castVote(authority, 1, 1);

        // check vote
        assertEq(nounsDAOSample.hasVoted(proxy), true);
        assertEq(nounsDAOSample.totalVotes(), 1);
        assertEq(nounsDAOSample.lastVoter(), proxy);
    }

    function testVote_selfProxy_failProxyNotCreated() public {
        // vote
        address[] memory authority = new address[](1);
        authority[0] = address(this);

        vm.expectRevert();
        alligator.castVote(authority, 1, 1);
    }

    // subdelegate
    function testVote_subdelegate() public {

        // create proxy
        address proxy = alligator.create(address(this));

        // subdelegate to alice
        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(Utils.alice, rules);

        // check vote
        assertEq(nounsDAOSample.hasVoted(proxy), false);
        assertEq(nounsDAOSample.totalVotes(), 0);
        assertEq(nounsDAOSample.lastVoter(), address(0));

        // alice vote
        address[] memory authority = new address[](2);
        authority[0] = address(this);
        authority[1] = Utils.alice;

        vm.startPrank(Utils.alice);
        alligator.castVote(authority, 1, 1);
        vm.stopPrank();

        // check vote
        assertEq(nounsDAOSample.hasVoted(proxy), true);
        assertEq(nounsDAOSample.totalVotes(), 1);
        assertEq(nounsDAOSample.lastVoter(), proxy);
    }

    // - nested
    function testVote_subdelegate_nested() public {

        // create proxy
        address proxy = alligator.create(address(this));

        // subdelegate
        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        // this -> alice
        alligator.subDelegate(Utils.alice, rules);

        // alice -> bob
        vm.startPrank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules);
        vm.stopPrank();

        // bob -> carol
        vm.startPrank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules);
        vm.stopPrank();

        // check vote
        assertEq(nounsDAOSample.hasVoted(proxy), false);
        assertEq(nounsDAOSample.totalVotes(), 0);
        assertEq(nounsDAOSample.lastVoter(), address(0));

        // carol vote
        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        vm.startPrank(Utils.carol);
        alligator.castVote(authority, 1, 1);
        vm.stopPrank();

        // check vote
        assertEq(nounsDAOSample.hasVoted(proxy), true);
        assertEq(nounsDAOSample.totalVotes(), 1);
        assertEq(nounsDAOSample.lastVoter(), proxy);
    }

    function testVote_subdelegate_nested_failRecalled() public {

        // create proxy
        alligator.create(address(this));

        // subdelegate
        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        // this -> alice
        alligator.subDelegate(Utils.alice, rules);

        // alice -> bob
        vm.startPrank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules);
        vm.stopPrank();

        // bob -> carol
        vm.startPrank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules);
        vm.stopPrank();

        // recall alice -> bob
        vm.startPrank(Utils.alice);
        alligator.subDelegate(
            Utils.bob,
            Rules({
                permissions: 0,
                maxRedelegations: 0,
                notValidBefore: 0,
                notValidAfter: 0,
                blocksBeforeVoteCloses: 0,
                customRule: address(0)
            })
        );
        vm.stopPrank();

        // carol vote
        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        vm.startPrank(Utils.carol);

        vm.expectRevert(abi.encodeWithSelector(Alligator.NotDelegated.selector, Utils.alice, Utils.bob, 0x01));
        alligator.castVote(authority, 1, 1);
        vm.stopPrank();
    }

    // - shared tree
    function testVote_subdelegate_sharedTree() public {

        // create proxy
        address proxy = alligator.create(address(this));

        // create proxy2
        address proxy2 = alligator.create(Utils.bob);

        // subdelegate
        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        // - this -> alice
        alligator.subDelegate(Utils.alice, rules);

        // - alice -> bob
        vm.startPrank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules);
        vm.stopPrank();

        // - bob -> carol
        vm.startPrank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules);
        vm.stopPrank();

        // check vote
        assertEq(nounsDAOSample.hasVoted(proxy), false);
        assertEq(nounsDAOSample.hasVoted(proxy2), false);
        assertEq(nounsDAOSample.totalVotes(), 0);
        assertEq(nounsDAOSample.lastVoter(), address(0));

        // carol vote (proxy)
        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        vm.startPrank(Utils.carol);
        alligator.castVote(authority, 1, 1);
        vm.stopPrank();

        // check vote
        assertEq(nounsDAOSample.hasVoted(proxy), true);
        assertEq(nounsDAOSample.hasVoted(proxy2), false);
        assertEq(nounsDAOSample.totalVotes(), 1);
        assertEq(nounsDAOSample.lastVoter(), proxy);

        // carol vote (proxy2)
        address[] memory authority2 = new address[](2);
        authority2[0] = Utils.bob;
        authority2[1] = Utils.carol;

        vm.startPrank(Utils.carol);
        alligator.castVote(authority2, 1, 1);
        vm.stopPrank();

        // check vote
        assertEq(nounsDAOSample.hasVoted(proxy), true);
        assertEq(nounsDAOSample.hasVoted(proxy2), true);
        assertEq(nounsDAOSample.totalVotes(), 2);
        assertEq(nounsDAOSample.lastVoter(), proxy2);
    }

    // batched
    function testVote_batched() public {

        // create proxy
        address proxy = alligator.create(address(this));

        // create proxy2
        address proxy2 = alligator.create(Utils.bob);

        // subdelegate
        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        // - this -> alice
        alligator.subDelegate(Utils.alice, rules);

        // - alice -> bob
        vm.startPrank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules);
        vm.stopPrank();

        // - bob -> carol
        vm.startPrank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules);
        vm.stopPrank();

        // check votes
        assertEq(nounsDAOSample.hasVoted(proxy), false);
        assertEq(nounsDAOSample.hasVoted(proxy2), false);
        assertEq(nounsDAOSample.totalVotes(), 0);
        assertEq(nounsDAOSample.lastVoter(), address(0));

        // carol vote batched
        address[] memory authority1 = new address[](4);
        authority1[0] = address(this);
        authority1[1] = Utils.alice;
        authority1[2] = Utils.bob;
        authority1[3] = Utils.carol;

        address[] memory authority2 = new address[](2);
        authority2[0] = Utils.bob;
        authority2[1] = Utils.carol;

        address[][] memory authorities = new address[][](2);
        authorities[0] = authority1;
        authorities[1] = authority2;

        vm.startPrank(Utils.carol);
        alligator.castVotesWithReasonBatched(authorities, 1, 1, "");
        vm.stopPrank();

        // check votes
        assertEq(nounsDAOSample.hasVoted(proxy), true);
        assertEq(nounsDAOSample.hasVoted(proxy2), true);
        assertEq(nounsDAOSample.totalVotes(), 2);
        assertEq(nounsDAOSample.lastVoter(), proxy2);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    rules                                   */
    /* -------------------------------------------------------------------------- */
    function testRules_failMaxRedelegations() public {
        // subdelegate
        Rules memory rules1 = Rules({
            permissions: 0x01,
            maxRedelegations: 1,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        Rules memory rules2 = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        // this -> alice (rules1)
        alligator.subDelegate(Utils.alice, rules1);

        // alice -> bob (rules2)
        vm.startPrank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules2);
        vm.stopPrank();

        // bob -> carol (rules2)
        vm.startPrank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules2);
        vm.stopPrank();

        // carol vote
        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        vm.startPrank(Utils.carol);

        vm.expectRevert(abi.encodeWithSelector(Alligator.TooManyRedelegations.selector, address(this), Utils.alice));
        alligator.castVote(authority, 1, 1);
        vm.stopPrank();
    }

    function testRules_failNoSigningPermission() public {
        // subdelegate
        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 1,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        // this -> alice
        alligator.subDelegate(Utils.alice, rules);

        // alice -> bob
        vm.startPrank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules);
        vm.stopPrank();

        // bob -> carol
        vm.startPrank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules);
        vm.stopPrank();

        // carol sign
        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        vm.startPrank(Utils.carol);

        vm.expectRevert(abi.encodeWithSelector(Alligator.NotDelegated.selector, address(this), Utils.alice, 0x02));
        alligator.sign(authority, keccak256(abi.encodePacked("hi")));
        vm.stopPrank();
    }

    /* -------------------------------------------------------------------------- */
    /*                                 signatures                                 */
    /* -------------------------------------------------------------------------- */
    // sign
    function testSigning() public {
        // hashes
        bytes32 hash1 = keccak256(abi.encodePacked("pass"));
        bytes32 hash2 = keccak256(abi.encodePacked("fail"));

        // create proxy
        address proxy = alligator.create(address(this));

        // check signature valid
        assertEq(IERC1271(proxy).isValidSignature(hash1, ""), bytes4(0));
        assertEq(IERC1271(proxy).isValidSignature(hash2, ""), bytes4(0));

        // sign
        address[] memory authority = new address[](1);
        authority[0] = address(this);

        alligator.sign(authority, hash1);

        // check signature valid
        assertEq(IERC1271(proxy).isValidSignature(hash1, ""), IERC1271.isValidSignature.selector);
        assertEq(IERC1271(proxy).isValidSignature(hash2, ""), bytes4(0));
    }

    function testSigning_nestedDelegate() public {
        // hashes
        bytes32 hash1 = keccak256(abi.encodePacked("pass"));

        // create proxy
        address proxy = alligator.create(address(this));

        // subdelegate
        Rules memory rules = Rules({
            permissions: 0x02,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        // this -> alice
        alligator.subDelegate(Utils.alice, rules);

        // alice -> bob
        vm.startPrank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules);
        vm.stopPrank();

        // bob -> carol
        vm.startPrank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules);
        vm.stopPrank();

        // check signature
        assertEq(IERC1271(proxy).isValidSignature(hash1, ""), bytes4(0));

        // carol sign
        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        vm.startPrank(Utils.carol);
        alligator.sign(authority, hash1);
        vm.stopPrank();

        // check signature
        assertEq(IERC1271(proxy).isValidSignature(hash1, ""), IERC1271.isValidSignature.selector);
    }

    function testSigning_nestedDelegate_failRecalled() public {

        // hashes
        bytes32 hash1 = keccak256(abi.encodePacked("pass"));

        // create proxy
        alligator.create(address(this));

        // subdelegate
        Rules memory rules = Rules({
            permissions: 0x02,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        // - this -> alice
        alligator.subDelegate(Utils.alice, rules);

        // - alice -> bob
        vm.startPrank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules);
        vm.stopPrank();

        // - bob -> carol
        vm.startPrank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules);
        vm.stopPrank();

        // recall alice -> bob
        vm.startPrank(Utils.alice);
        alligator.subDelegate(
            Utils.bob,
            Rules({
                permissions: 0,
                maxRedelegations: 0,
                notValidBefore: 0,
                notValidAfter: 0,
                blocksBeforeVoteCloses: 0,
                customRule: address(0)
            })
        );
        vm.stopPrank();
        
        // carol sign
        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        vm.startPrank(Utils.carol);

        vm.expectRevert(abi.encodeWithSelector(Alligator.NotDelegated.selector, Utils.alice, Utils.bob, 0x02));
        alligator.sign(authority, hash1);
        vm.stopPrank();
    }

    // offchain
    function testOffchainSignatures() public {
        // account
        uint256 privateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        address signer = vm.addr(privateKey);

        // hashes
        bytes32 hash1 = keccak256(abi.encodePacked("pass"));

        // create proxy
        address proxy = alligator.create(address(this));

        // subdelegate
        Rules memory rules = Rules({
            permissions: 0x02,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        // - this -> alice
        alligator.subDelegate(Utils.alice, rules);

        // - alice -> bob
        vm.startPrank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules);
        vm.stopPrank();

        // - bob -> carol
        vm.startPrank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules);
        vm.stopPrank();

        // - carol -> signer
        vm.startPrank(Utils.carol);
        alligator.subDelegate(signer, rules);
        vm.stopPrank();

        // sign
        address[] memory authority = new address[](5);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;
        authority[4] = signer;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash1);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory data = abi.encode(authority, signature);

        // check signature
        assertEq(IERC1271(proxy).isValidSignature(hash1, data), IERC1271.isValidSignature.selector);
    }

    function testOffchainSignatures_failInvalidSignature() public {
        // account
        uint256 privateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        address signer = vm.addr(privateKey);

        // hashes
        bytes32 hash1 = keccak256(abi.encodePacked("pass"));
        bytes32 hash2 = keccak256(abi.encodePacked("fake"));

        // create proxy
        address proxy = alligator.create(address(this));

        // subdelegate
        Rules memory rules = Rules({
            permissions: 0x02,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        // - this -> alice
        alligator.subDelegate(Utils.alice, rules);

        // - alice -> bob
        vm.startPrank(Utils.alice);
        alligator.subDelegate(Utils.bob, rules);
        vm.stopPrank();

        // - bob -> carol
        vm.startPrank(Utils.bob);
        alligator.subDelegate(Utils.carol, rules);
        vm.stopPrank();

        // - carol -> signer
        vm.startPrank(Utils.carol);
        alligator.subDelegate(signer, rules);
        vm.stopPrank();

        // sign
        address[] memory authority = new address[](5);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;
        authority[4] = signer;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash1);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory data = abi.encode(authority, signature);

        // check signature
        vm.expectRevert(abi.encodeWithSelector(Alligator.NotDelegated.selector, signer, 0x329d9D7C45B6cF10a96dEdDdC82e74621EFe5796, 0x02));
        IERC1271(proxy).isValidSignature(hash2, data);
    }
}