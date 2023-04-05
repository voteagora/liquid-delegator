// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {AlligatorV2} from "src/v2/AlligatorV2.sol";
import "src/interfaces/IAlligatorV2.sol";
import "./Addresses.sol";
import {IGovernorMock} from "../mock/IGovernorMock.sol";
import {CREATE3Factory} from "create3-factory/CREATE3Factory.sol";

abstract contract SetupV2 is Test {
    // =============================================================
    //                  ERRORS & EVENTS & CONSTANTS
    // =============================================================

    error BadSignature();
    error InvalidAuthorityChain();
    error NotDelegated(address from, address to, uint256 requiredPermissions);
    error TooManyRedelegations(address from, address to);
    error NotValidYet(address from, address to, uint256 willBeValidFrom);
    error NotValidAnymore(address from, address to, uint256 wasValidUntil);
    error TooEarly(address from, address to, uint256 blocksBeforeVoteCloses);
    error InvalidCustomRule(address from, address to, address customRule);

    event ProxyDeployed(address indexed owner, Rules proxyRules, address proxy);
    event SubDelegation(address indexed from, address indexed to, Rules subDelegateRules);
    event SubDelegations(address indexed from, address[] to, Rules[] subDelegateRules);
    event SubDelegationProxy(
        address indexed from,
        address indexed to,
        Rules subDelegateRules,
        address indexed proxyOwner,
        Rules proxyRules
    );
    event SubDelegationProxies(
        address indexed from,
        address[] to,
        Rules[] subDelegateRules,
        address indexed proxyOwner,
        Rules proxyRules
    );
    event VoteCast(
        address indexed proxy,
        address indexed voter,
        address[] authority,
        uint256 proposalId,
        uint8 support
    );
    event VotesCast(
        address[] proxies,
        address indexed voter,
        address[][] authorities,
        uint256 proposalId,
        uint8 support
    );
    event Signed(address indexed proxy, address[] authority, bytes32 messageHash);

    uint8 internal constant PERMISSION_VOTE = 1;
    uint8 internal constant PERMISSION_SIGN = 1 << 1;
    uint8 internal constant PERMISSION_PROPOSE = 1 << 2;

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    bytes32 internal constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    // =============================================================
    //                            STORAGE
    // =============================================================

    CREATE3Factory _create3Factory;
    AlligatorV2 internal alligator;
    IGovernorMock internal governor;
    address internal root;
    Rules internal baseRules =
        Rules(
            7, // All permissions
            255, // Max redelegations
            0,
            0,
            0,
            address(0)
        );

    // =============================================================
    //                             SETUP
    // =============================================================

    function setUp() public virtual {
        _create3Factory = new CREATE3Factory();
    }
}

interface DelegateToken is IERC721 {
    function delegate(address delegatee) external;
}
