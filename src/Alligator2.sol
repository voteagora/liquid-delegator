// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IGovernorBravo} from "./interfaces/IGovernorBravo.sol";
import {INounsDAOV2} from "./interfaces/INounsDAOV2.sol";
import {IRule} from "./interfaces/IRule.sol";

struct Rules {
    uint8 permissions;
    uint8 maxRedelegations;
    uint32 notValidBefore;
    uint32 notValidAfter;
    uint16 blocksBeforeVoteCloses;
    address customRule;
}

contract Endpoint {
    address internal immutable owner;
    address internal immutable governor;

    constructor(address _governor) {
        owner = msg.sender;
        governor = _governor;
    }

    fallback() external payable {
        require(msg.sender == owner);
        address addr = governor;

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := call(gas(), addr, callvalue(), 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}

contract Alligator2 {
    INounsDAOV2 public immutable governor;

    mapping(address => address) owners;
    mapping(address => mapping(address => mapping(address => Rules))) public subDelegations;

    uint8 internal constant PERMISSION_VOTE = 0x01;
    uint8 internal constant PERMISSION_SIGN = 0x02;
    uint8 internal constant PERMISSION_PROPOSE = 0x04;

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    bytes32 internal constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    event AlligatorDeployed(address indexed owner, address alligator);
    event SubDelegation(address indexed root, address indexed from, address indexed to, Rules rules);
    event VoteCast(address indexed root, address indexed voter, address[] authority, uint256 proposalId, uint8 support);

    error BadSignature();
    error NotDelegated(address root, address from, address to, uint8 requiredPermissions);
    error NotValidYet(address root, address from, address to, uint32 willBeValidFrom);
    error NotValidAnymore(address root, address from, address to, uint32 wasValidUntil);
    error TooEarly(address root, address from, address to, uint32 blocksBeforeVoteCloses);
    error InvalidCustomRule(address root, address customRule);

    constructor(INounsDAOV2 _governor) {
        governor = _governor;
    }

    function create(address owner) external returns (address endpoint) {
        endpoint = address(new Endpoint(address(governor)));
        emit AlligatorDeployed(owner, endpoint);

        owners[endpoint] = owner;
    }

    function propose(
        address[] calldata authority,
        address[] calldata targets,
        uint256[] calldata values,
        string[] calldata signatures,
        bytes[] calldata calldatas,
        string calldata description
    ) external returns (uint256 proposalId) {
        // Create a proposal first so the custom rules can validate it
        proposalId = INounsDAOV2(authority[0]).propose(targets, values, signatures, calldatas, description);
        validate(msg.sender, authority, PERMISSION_PROPOSE, proposalId, 0xFF);
    }

    function castVote(address[] calldata authority, uint256 proposalId, uint8 support) external {
        validate(msg.sender, authority, PERMISSION_VOTE, proposalId, support);
        INounsDAOV2(authority[0]).castVote(proposalId, support);
        emit VoteCast(authority[0], msg.sender, authority, proposalId, support);
    }

    function castVoteWithReason(address[] calldata authority, uint256 proposalId, uint8 support, string calldata reason)
        external
    {
        validate(msg.sender, authority, PERMISSION_VOTE, proposalId, support);
        INounsDAOV2(authority[0]).castVoteWithReason(proposalId, support, reason);
        emit VoteCast(authority[0], msg.sender, authority, proposalId, support);
    }

    function castVoteBySig(
        address[] calldata authority,
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 domainSeparator =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Alligator"), block.chainid, address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);

        if (signatory != address(0)) {
            revert BadSignature();
        }

        validate(signatory, authority, PERMISSION_VOTE, proposalId, support);
        INounsDAOV2(authority[0]).castVote(proposalId, support);
        emit VoteCast(authority[0], signatory, authority, proposalId, support);
    }

    function subDelegate(address root, address to, Rules calldata rules) external {
        subDelegations[root][msg.sender][to] = rules;
        emit SubDelegation(root, msg.sender, to, rules);
    }

    function validate(
        address sender,
        address[] calldata authority,
        uint8 permissions,
        uint256 proposalId,
        uint8 support
    ) internal view {
        address root = authority[0];
        address account = owners[root];

        if (account == sender) {
            return;
        }

        INounsDAOV2.ProposalCondensed memory proposal = governor.proposals(proposalId);

        for (uint256 i = 1; i < authority.length; i++) {
            address to = authority[i];
            Rules memory rules = subDelegations[root][account][to];

            if (rules.permissions & permissions != permissions) {
                revert NotDelegated(root, account, to, permissions);
            }
            // TODO: check redelegations limit
            if (block.timestamp < rules.notValidBefore) {
                revert NotValidYet(root, account, to, rules.notValidBefore);
            }
            if (rules.notValidAfter != 0 && block.timestamp > rules.notValidAfter) {
                revert NotValidAnymore(root, account, to, rules.notValidAfter);
            }
            if (rules.blocksBeforeVoteCloses != 0 && proposal.endBlock - block.number > rules.blocksBeforeVoteCloses) {
                revert TooEarly(root, account, to, rules.blocksBeforeVoteCloses);
            }
            if (rules.customRule != address(0)) {
                bytes4 selector = IRule(rules.customRule).validate(address(governor), sender, proposalId, support);
                if (selector != IRule.validate.selector) {
                    revert InvalidCustomRule(root, rules.customRule);
                }
            }

            account = to;
        }

        if (account == sender) {
            return;
        }

        revert NotDelegated(root, account, sender, permissions);
    }
}
