// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./SetupV2.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract AlligatorV2Base is SetupV2 {
    function testDeploy() public {
        assertEq(Ownable(address(alligator)).owner(), address(this));
    }

    function testCreate() public {
        address computedAddress = alligator.proxyAddress(Utils.bob, baseRules);
        assertTrue(computedAddress.code.length == 0);
        alligator.create(Utils.bob, baseRules, false);
        assertTrue(computedAddress.code.length != 0);
    }

    function testProxyAddressMatches() public {
        address proxy = alligator.create(Utils.bob, baseRules, true);
        assertEq(alligator.proxyAddress(Utils.bob, baseRules), proxy);
    }

    function testCastVote() public {
        address[] memory authority = new address[](1);
        authority[0] = address(this);

        vm.expectEmit(true, true, false, true);
        emit VoteCast(alligator.proxyAddress(address(this), baseRules), address(this), authority, 1, 1);
        alligator.castVote(baseRules, authority, 1, 1);

        address[] memory authority2 = new address[](2);
        authority2[0] = address(Utils.alice);
        authority2[1] = address(this);

        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.alice, baseRules, address(this), baseRules);

        vm.expectEmit(true, true, false, true);
        emit VoteCast(alligator.proxyAddress(address(Utils.alice), baseRules), address(this), authority2, 1, 1);
        alligator.castVote(baseRules, authority2, 1, 1);
    }

    function testCastVoteWithReason() public {
        address[] memory authority = new address[](1);
        authority[0] = address(this);

        vm.expectEmit(true, true, false, true);
        emit VoteCast(alligator.proxyAddress(address(this), baseRules), address(this), authority, 1, 1);
        alligator.castVoteWithReason(baseRules, authority, 1, 1, "reason");

        address[] memory authority2 = new address[](2);
        authority2[0] = address(Utils.alice);
        authority2[1] = address(this);

        vm.prank(Utils.alice);
        alligator.subDelegate(Utils.alice, baseRules, address(this), baseRules);

        vm.expectEmit(true, true, false, true);
        emit VoteCast(alligator.proxyAddress(address(Utils.alice), baseRules), address(this), authority2, 1, 1);
        alligator.castVoteWithReason(baseRules, authority2, 1, 1, "reason");
    }

    function testCastVotesWithReasonBatched() public {
        (address[][] memory authorities, address[] memory proxies, Rules[] memory proxyRules) = _formatBatchData();

        vm.prank(Utils.carol);
        vm.expectEmit(true, true, false, true);
        emit VotesCast(proxies, Utils.carol, authorities, 1, 1);
        alligator.castVotesWithReasonBatched(proxyRules, authorities, 1, 1, "");

        assertEq(governor.hasVoted(alligator.proxyAddress(address(this), baseRules)), true);
        assertEq(governor.hasVoted(alligator.proxyAddress(Utils.bob, baseRules)), true);
        assertEq(governor.totalVotes(), 2);
    }

    // Run `forge test` with --gas-price param to set the gas price
    function testCastRefundableVotesWithReasonBatched_withTxOrigin() public {
        uint256 refundAmount = 206108 * tx.gasprice;
        vm.deal(address(governor), 1 ether);

        (address[][] memory authorities, , Rules[] memory proxyRules) = _formatBatchData();

        vm.prank(Utils.carol, Utils.carol);
        alligator.castRefundableVotesWithReasonBatched{gas: 1e9}(proxyRules, authorities, 1, 1, "");

        assertEq(governor.hasVoted(alligator.proxyAddress(address(this), baseRules)), true);
        assertEq(governor.hasVoted(alligator.proxyAddress(Utils.bob, baseRules)), true);
        assertEq(governor.totalVotes(), 2);
        assertApproxEqAbs(Utils.carol.balance, refundAmount, 2e6);
    }

    function testPropose() public {
        address[] memory authority = new address[](1);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        authority[0] = address(this);
        targets[0] = address(1);
        values[0] = 1;
        signatures[0] = "";
        calldatas[0] = "";

        alligator.propose(baseRules, authority, targets, values, signatures, calldatas, "");
    }

    function testSubDelegate_proxyCreated() public {
        vm.prank(Utils.alice);

        vm.expectEmit(true, true, false, true);
        emit SubDelegationProxy(Utils.alice, address(this), baseRules, Utils.alice, baseRules);
        alligator.subDelegate(Utils.alice, baseRules, address(this), baseRules);
        assertTrue(alligator.proxyAddress(Utils.alice, baseRules).code.length != 0);
    }

    function testSubDelegateBatched() public {
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

        vm.prank(Utils.alice);

        vm.expectEmit(true, true, false, true);
        emit SubDelegationProxies(Utils.alice, targets, rules, Utils.alice, baseRules);
        alligator.subDelegateBatched(Utils.alice, baseRules, targets, rules);
        vm.prank(Utils.bob);
        alligator.subDelegateBatched(Utils.alice, baseRules, targets, rules);

        assertTrue(alligator.proxyAddress(Utils.alice, baseRules).code.length != 0);

        (uint8 bobPermissions, , , , , ) = alligator.subDelegationsProxy(
            keccak256(abi.encode(Utils.alice, baseRules)),
            Utils.alice,
            Utils.bob
        );
        assertEq(bobPermissions, 0x01);

        (uint8 carolPermissions, , , , , ) = alligator.subDelegationsProxy(
            keccak256(abi.encode(Utils.alice, baseRules)),
            Utils.alice,
            Utils.carol
        );
        assertEq(carolPermissions, 0x02);
    }

    function testNestedSubDelegate() public {
        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(address(this), baseRules, Utils.alice, rules);
        vm.prank(Utils.alice);
        alligator.subDelegate(address(this), baseRules, Utils.bob, rules);
        vm.prank(Utils.bob);
        alligator.subDelegate(address(this), baseRules, Utils.carol, rules);

        vm.prank(Utils.carol);
        alligator.castVote(baseRules, authority, 1, 1);
    }

    function testSharedSubDelegateTree() public {
        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        address proxy2 = alligator.create(Utils.bob, baseRules, true);
        address[] memory authority2 = new address[](2);
        authority2[0] = Utils.bob;
        authority2[1] = Utils.carol;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(address(this), baseRules, Utils.alice, rules);
        vm.prank(Utils.alice);
        alligator.subDelegate(address(this), baseRules, Utils.bob, rules);
        vm.prank(Utils.bob);
        alligator.subDelegate(address(this), baseRules, Utils.carol, rules);
        vm.prank(Utils.bob);
        alligator.subDelegate(Utils.bob, baseRules, Utils.carol, rules);

        vm.prank(Utils.carol);
        alligator.castVote(baseRules, authority, 1, 1);
        assertEq(governor.lastVoter(), root);

        vm.prank(Utils.carol);
        alligator.castVote(baseRules, authority2, 1, 1);
        assertEq(governor.lastVoter(), proxy2);
    }

    function testNestedUnDelegate() public {
        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(address(this), baseRules, Utils.alice, rules);
        vm.prank(Utils.alice);
        alligator.subDelegate(address(this), baseRules, Utils.bob, rules);
        vm.prank(Utils.bob);
        alligator.subDelegate(address(this), baseRules, Utils.carol, rules);

        vm.prank(Utils.alice);
        alligator.subDelegate(
            address(this),
            baseRules,
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

        vm.prank(Utils.carol);
        vm.expectRevert(abi.encodeWithSelector(NotDelegated.selector, Utils.alice, Utils.bob, PERMISSION_VOTE));
        alligator.castVote(baseRules, authority, 1, 1);
    }

    function testSubDelegateAll() public {
        alligator.create(Utils.alice, baseRules, false);

        vm.prank(Utils.alice);
        vm.expectEmit(true, true, false, true);
        emit SubDelegation(Utils.alice, address(this), baseRules);
        alligator.subDelegateAll(address(this), baseRules);

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });
        alligator.create(Utils.alice, rules, false);

        address[] memory authority = new address[](2);
        authority[0] = Utils.alice;
        authority[1] = address(this);

        alligator.castVote(baseRules, authority, 1, 1);
        alligator.castVote(rules, authority, 1, 1);
        (uint8 permissions, , , , , ) = alligator.subDelegations(Utils.alice, address(this));
        assertEq(permissions, baseRules.permissions);
    }

    function testSubDelegateAllBatched() public {
        alligator.create(Utils.alice, baseRules, false);

        address[] memory to = new address[](2);
        to[0] = address(this);
        to[1] = Utils.bob;

        Rules[] memory proxyRules = new Rules[](2);
        proxyRules[0] = baseRules;
        proxyRules[1] = baseRules;

        vm.prank(Utils.alice);
        vm.expectEmit(true, true, false, true);
        emit SubDelegations(Utils.alice, to, proxyRules);
        alligator.subDelegateAllBatched(to, proxyRules);

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });
        alligator.create(Utils.alice, rules, false);

        address[] memory authority1 = new address[](2);
        authority1[0] = Utils.alice;
        authority1[1] = address(this);

        address[] memory authority2 = new address[](2);
        authority2[0] = Utils.alice;
        authority2[1] = Utils.bob;

        alligator.castVote(baseRules, authority1, 1, 1);
        alligator.castVote(rules, authority1, 1, 1);
        (uint8 permissions, , , , , ) = alligator.subDelegations(Utils.alice, address(this));
        assertEq(permissions, baseRules.permissions);

        vm.startPrank(Utils.bob);
        alligator.castVote(baseRules, authority2, 1, 1);
        alligator.castVote(rules, authority2, 1, 1);
        (uint8 bobPermissions, , , , , ) = alligator.subDelegations(Utils.alice, address(this));
        assertEq(bobPermissions, baseRules.permissions);
        vm.stopPrank();
    }

    function testSupportsSigning() public {
        bytes32 hash1 = keccak256(abi.encodePacked("pass"));
        bytes32 hash2 = keccak256(abi.encodePacked("fail"));

        assertEq(IERC1271(root).isValidSignature(hash2, ""), bytes4(0));

        address[] memory authority = new address[](1);
        authority[0] = address(this);
        alligator.sign(baseRules, authority, hash1);

        assertEq(IERC1271(root).isValidSignature(hash1, ""), IERC1271.isValidSignature.selector);
        assertEq(IERC1271(root).isValidSignature(hash2, ""), bytes4(0));
    }

    function testNestedSubDelegateSigning() public {
        bytes32 hash1 = keccak256(abi.encodePacked("pass"));

        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        Rules memory rules = Rules({
            permissions: 0x02,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(address(this), baseRules, Utils.alice, rules);
        vm.prank(Utils.alice);
        alligator.subDelegate(address(this), baseRules, Utils.bob, rules);
        vm.prank(Utils.bob);
        alligator.subDelegate(address(this), baseRules, Utils.carol, rules);

        vm.prank(Utils.carol);
        alligator.sign(baseRules, authority, hash1);
        assertEq(IERC1271(root).isValidSignature(hash1, ""), IERC1271.isValidSignature.selector);
    }

    function testNestedUnDelegateSigning() public {
        bytes32 hash1 = keccak256(abi.encodePacked("pass"));

        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        Rules memory rules = Rules({
            permissions: 0x02,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(address(this), baseRules, Utils.alice, rules);
        vm.prank(Utils.alice);
        alligator.subDelegate(address(this), baseRules, Utils.bob, rules);
        vm.prank(Utils.bob);
        alligator.subDelegate(address(this), baseRules, Utils.carol, rules);

        vm.prank(Utils.alice);
        alligator.subDelegate(
            address(this),
            baseRules,
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

        vm.prank(Utils.carol);
        vm.expectRevert(abi.encodeWithSelector(NotDelegated.selector, Utils.alice, Utils.bob, PERMISSION_SIGN));
        alligator.sign(baseRules, authority, hash1);
        assertEq(IERC1271(root).isValidSignature(hash1, ""), bytes4(0));
    }

    function testIsValidSignature() public {
        uint256 privateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        address signer = vm.addr(privateKey);
        bytes32 hash1 = keccak256(abi.encodePacked("data"));
        bytes32 hash2 = keccak256(abi.encodePacked("fake"));

        address[] memory authority = new address[](5);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;
        authority[4] = signer;

        Rules memory rules = Rules({
            permissions: 0x02,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(address(this), baseRules, Utils.alice, rules);
        vm.prank(Utils.alice);
        alligator.subDelegate(address(this), baseRules, Utils.bob, rules);
        vm.prank(Utils.bob);
        alligator.subDelegate(address(this), baseRules, Utils.carol, rules);
        vm.prank(Utils.carol);
        alligator.subDelegate(address(this), baseRules, signer, rules);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash1);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory data = abi.encode(authority, signature);

        assertEq(IERC1271(root).isValidSignature(hash1, data), IERC1271.isValidSignature.selector);

        // Different hash means erecover returns a different user
        vm.expectRevert();
        IERC1271(root).isValidSignature(hash2, data);
    }

    function testIsValidSignature_signingBug() public {
        // create an address from private key = 0x01 that should have no authority
        uint PRIVATE_KEY = 1;
        address signer = vm.addr(PRIVATE_KEY);

        // sign any message with that private key
        bytes32 hash = keccak256(abi.encodePacked("i can make you sign anything"));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRIVATE_KEY, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // set the authority chain to be only my own address
        address[] memory authority = new address[](1);
        authority[0] = signer;

        // create the signature data, which consists of authority chain and signature
        bytes memory digest = abi.encode(authority, signature);

        // confirm that the call is reverted with `InvalidAuthorityChain()`
        vm.expectRevert(InvalidAuthorityChain.selector);
        IERC1271(root).isValidSignature(hash, digest);
    }

    function testPause() public {
        address[] memory authority = new address[](1);
        address[][] memory authorities = new address[][](1);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        string[] memory signatures = new string[](1);
        bytes[] memory calldatas = new bytes[](1);
        Rules[] memory proxyRules = new Rules[](1);
        authority[0] = address(this);
        authorities[0] = authority;
        targets[0] = address(1);
        values[0] = 1;
        signatures[0] = "";
        calldatas[0] = "";
        proxyRules[0] = baseRules;

        alligator._togglePause();

        vm.expectRevert("Pausable: paused");
        alligator.castVote(baseRules, authority, 1, 1);
        vm.expectRevert("Pausable: paused");
        alligator.castVoteWithReason(baseRules, authority, 1, 1, "reason");
        vm.expectRevert("Pausable: paused");
        alligator.castVotesWithReasonBatched(proxyRules, authorities, 1, 1, "");
        vm.expectRevert("Pausable: paused");
        alligator.castRefundableVotesWithReasonBatched{gas: 1e9}(proxyRules, authorities, 1, 1, "");
        vm.expectRevert("Pausable: paused");
        alligator.propose(baseRules, authority, targets, values, signatures, calldatas, "");
        vm.expectRevert("Pausable: paused");
        alligator.sign(baseRules, authority, keccak256(abi.encodePacked("test")));
    }

    // // =============================================================
    // //                           REVERTS
    // // =============================================================

    function testRevert_castVote_validateCheck() public {
        address[] memory authority = new address[](1);
        authority[0] = address(this);
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(NotDelegated.selector, address(this), address(1), PERMISSION_VOTE));
        alligator.castVote(baseRules, authority, 1, 1);
    }

    function testRevert_castVoteWithReason_validateCheck() public {
        address[] memory authority = new address[](1);
        authority[0] = address(this);
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(NotDelegated.selector, address(this), address(1), PERMISSION_VOTE));
        alligator.castVoteWithReason(baseRules, authority, 1, 1, "reason");
    }

    function testRevert_validate_MaxRedelegations() public {
        address[] memory authority = new address[](4);
        authority[0] = address(this);
        authority[1] = Utils.alice;
        authority[2] = Utils.bob;
        authority[3] = Utils.carol;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 1,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(address(this), baseRules, Utils.alice, rules);
        vm.prank(Utils.alice);
        rules.maxRedelegations = 255;
        alligator.subDelegate(address(this), baseRules, Utils.bob, rules);
        vm.prank(Utils.bob);
        alligator.subDelegate(address(this), baseRules, Utils.carol, rules);

        vm.prank(Utils.carol);
        vm.expectRevert(abi.encodeWithSelector(TooManyRedelegations.selector, address(this), Utils.alice));
        alligator.castVote(baseRules, authority, 1, 1);

        address[] memory authority2 = new address[](3);
        authority2[0] = address(this);
        authority2[1] = Utils.alice;
        authority2[2] = Utils.bob;

        vm.prank(Utils.bob);
        alligator.castVote(baseRules, authority2, 1, 1);
    }

    function testRevert_validate_NotValidBefore() public {
        address[] memory authority = new address[](2);
        authority[0] = address(this);
        authority[1] = Utils.alice;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 1,
            notValidBefore: uint32(block.timestamp + 1e3),
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(address(this), baseRules, Utils.alice, rules);

        vm.prank(Utils.alice);
        vm.expectRevert(abi.encodeWithSelector(NotValidYet.selector, address(this), Utils.alice, rules.notValidBefore));
        alligator.castVote(baseRules, authority, 1, 1);
    }

    function testRevert_validate_NotValidAnymore() public {
        address[] memory authority = new address[](2);
        authority[0] = address(this);
        authority[1] = Utils.alice;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 1,
            notValidBefore: 0,
            notValidAfter: 90,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(address(this), baseRules, Utils.alice, rules);

        vm.warp(100);
        vm.prank(Utils.alice);
        vm.expectRevert(
            abi.encodeWithSelector(NotValidAnymore.selector, address(this), Utils.alice, rules.notValidAfter)
        );
        alligator.castVote(baseRules, authority, 1, 1);
    }

    function testRevert_togglePause_notOwner() public {
        vm.prank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        alligator._togglePause();
    }

    function testRevert_validate_TooEarly() public {
        address[] memory authority = new address[](2);
        authority[0] = address(this);
        authority[1] = Utils.alice;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 1,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 99,
            customRule: address(0)
        });

        alligator.subDelegate(address(this), baseRules, Utils.alice, rules);

        vm.prank(Utils.alice);
        vm.expectRevert(
            abi.encodeWithSelector(TooEarly.selector, address(this), Utils.alice, rules.blocksBeforeVoteCloses)
        );
        alligator.castVote(baseRules, authority, 1, 1);
    }

    function _formatBatchData()
        internal
        returns (address[][] memory authorities, address[] memory proxies, Rules[] memory proxyRules)
    {
        address[] memory authority1 = new address[](4);
        authority1[0] = address(this);
        authority1[1] = Utils.alice;
        authority1[2] = Utils.bob;
        authority1[3] = Utils.carol;

        address[] memory authority2 = new address[](2);
        authority2[0] = Utils.bob;
        authority2[1] = Utils.carol;

        authorities = new address[][](2);
        authorities[0] = authority1;
        authorities[1] = authority2;

        Rules memory rules = Rules({
            permissions: 0x01,
            maxRedelegations: 255,
            notValidBefore: 0,
            notValidAfter: 0,
            blocksBeforeVoteCloses: 0,
            customRule: address(0)
        });

        alligator.subDelegate(address(this), baseRules, Utils.alice, rules);
        vm.prank(Utils.alice);
        alligator.subDelegate(address(this), baseRules, Utils.bob, rules);
        vm.prank(Utils.bob);
        alligator.subDelegate(address(this), baseRules, Utils.carol, rules);
        vm.prank(Utils.bob);
        alligator.subDelegate(Utils.bob, baseRules, Utils.carol, rules);

        proxies = new address[](2);
        proxies[0] = alligator.proxyAddress(address(this), baseRules);
        proxies[1] = alligator.proxyAddress(Utils.bob, baseRules);

        proxyRules = new Rules[](2);
        proxyRules[0] = baseRules;
        proxyRules[1] = baseRules;
    }
}
