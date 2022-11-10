// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IGovernorBravo} from "./interfaces/IGovernorBravo.sol";
import {INounsDAOV2} from "./interfaces/INounsDAOV2.sol";
import {IRule} from "./interfaces/IRule.sol";

// Batch vote from different aligators
// How will the frontend know which aligators are available?
// How Prop House works: signatures EIP-1271

struct Delegation {
    address to;
    uint256 until;
    uint256 redelegations;
}

/*

Seneca uses Aligator
Seneca appoints Alex
Seneca appoints Bob
Alex appoints Yitong
Seneca unappoints Alex
Yitong can't vote
Bob can vote

Or maybe we compute whenever someone can vote during 
the delegation process

Or maybe we don't let appoint more than 1 person?

Seneca uses Aligator
Seneca appoints Alex
Alex appoints Yitong

Can Yitong vote? Need to either supply the voting authority chain
or the voting authority chain needs to be stored in the contract
*/

// Rules
// - Sub-delegate up to X times
// - Sub-delegate for X amount of time
// - Allow voting only in the last X hours (backup)
// - Allow voting on prop house (signatures)
// - Props that don't upgrade the code
// - Props that only distribute eth up to X
// - Custom rules (call a contract)
// - Can receive refunds

// - Pull all proposal targets

enum Clearance {
    None,
    Propose,
    Vote,
    Execute
}

struct Rules {
    bool active; // 8
    uint8 maxRedelegations; // 16
    uint32 notValidBefore; // 48
    uint32 notValidAfter; // 80
    uint16 blocksBeforeVoteCloses; // 96
    bool canSignProposals; // 104
    bool canReceiveRefunds; // 112
    uint32 maxEthValue; // 144
    bool canCallContracts; // 152
    //
    address customRule;
}

contract AligatorWithRules {
    address public immutable owner;
    IGovernorBravo public immutable governor;
    mapping(address => mapping(address => Rules)) public subDelegations;

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    bytes32 internal constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    event SubDelegation(address indexed from, address indexed to, Rules rules);
    // Emit event when casting vote

    error NotDelegated(address from, address to);
    error ChainTooLong();

    constructor(address _owner, IGovernorBravo _governor) {
        owner = _owner;
        governor = _governor;
    }

    function castVote(address[] calldata authority, uint256 proposalId, uint8 support) external {
        validate(msg.sender, authority, proposalId, support);
        governor.castVote(proposalId, support);
    }

    function castVoteWithReason(address[] calldata authority, uint256 proposalId, uint8 support, string calldata reason)
        external
    {
        validate(msg.sender, authority, proposalId, support);
        INounsDAOV2(address(governor)).castVoteWithReason(proposalId, support, reason);
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
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("Aligator"), block.chainid, address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);

        require(signatory != address(0), "NounsDAO::castVoteBySig: invalid signature");
        validate(signatory, authority, proposalId, support);
        governor.castVote(proposalId, support);
    }

    function subDelegate(address to, Rules calldata rules) external {
        subDelegations[msg.sender][to] = rules;
        emit SubDelegation(msg.sender, to, rules);
    }

    function validate(address sender, address[] calldata authority, uint256 proposalId, uint8 support) internal view {
        address account = owner;

        if (account == sender) {
            return;
        }

        INounsDAOV2.ProposalCondensed memory proposal = INounsDAOV2(address(governor)).proposals(proposalId);
        (address[] memory targets, uint256[] memory values, string[] memory signatures, bytes[] memory calldatas) =
            INounsDAOV2(address(governor)).getActions(proposalId);

        for (uint256 i = 0; i < authority.length; i++) {
            address to = authority[i];
            Rules memory rules = subDelegations[account][to];
            if (!rules.active) {
                revert NotDelegated(account, to);
            }
            if (block.timestamp < rules.notValidBefore) {
                revert NotDelegated(account, to);
            }
            if (block.timestamp > rules.notValidAfter) {
                revert NotDelegated(account, to);
            }
            if (proposal.endBlock - block.number > rules.blocksBeforeVoteCloses) {
                revert NotDelegated(account, to);
            }
            if (rules.customRule != address(0)) {
                bytes4 selector = IRule(rules.customRule).validate(sender, proposalId, support);
                require(selector == IRule.validate.selector, "Invalid custom rule");
            }
            account = to;
        }

        if (account == sender) {
            return;
        }

        revert NotDelegated(account, sender);
    }
}

contract AligatorFactory {
    IGovernorBravo public immutable governor;

    event AligatorDeployed(address indexed owner, address aligator);

    constructor(IGovernorBravo _governor) {
        governor = _governor;
    }

    function create(address owner) external returns (AligatorWithRules aligator) {
        bytes32 salt = bytes32(uint256(uint160(owner)));
        aligator = new AligatorWithRules{salt: salt}(owner, governor);
        emit AligatorDeployed(owner, address(aligator));
    }
}

contract AligatorOffchainAuthority {
    address public immutable owner;
    IGovernorBravo public immutable governor;
    mapping(address => mapping(address => bytes)) public subDelegations;

    event SubDelegation(address indexed from, address indexed to, bytes rules);
    // Emit event when casting vote

    error NotDelegated(address from, address to);

    constructor(IGovernorBravo _governor) {
        owner = msg.sender;
        governor = _governor;
    }

    function castVote(address[] calldata authority, uint256 proposalId, uint8 support) external {
        require(canVote(authority));
        governor.castVote(proposalId, support);
    }

    function subDelegate(address account, bytes calldata rules) external {
        subDelegations[msg.sender][account] = rules;
        emit SubDelegation(msg.sender, account, rules);
    }

    function canVote(address[] calldata authority) internal view returns (bool) {
        address account = owner;
        for (uint256 i = 0; i < authority.length; i++) {
            address to = authority[i];
            if (subDelegations[account][to].length == 0) {
                revert NotDelegated(account, to);
            }
            account = to;
        }

        return account == msg.sender;
    }
}

contract CanVoteOnlyBeforeTimestamp is IRule {
    uint256 public immutable timestamp;

    constructor(uint256 _timestamp) {
        timestamp = _timestamp;
    }

    function check(address voter, uint256 proposalId, uint8 support, bytes calldata rule)
        external
        view
        override
        returns (bool)
    {
        return block.timestamp <= timestamp;
    }
}

contract CanVoteOnlyWithinBlocks is IRule {
    INounsDAOV2 private immutable dao;
    uint256 private immutable blocks;

    constructor(INounsDAOV2 _dao, uint256 _blocks) {
        dao = _dao;
        blocks = _blocks;
    }

    function check(address voter, uint256 proposalId, uint8 support, bytes calldata rule)
        external
        view
        override
        returns (bool)
    {
        INounsDAOV2.ProposalCondensed memory proposal = dao.proposals(proposalId);
        return proposal.endBlock + blocks >= block.number;
    }
}

contract ValueLimit is IRule {
    INounsDAOV2 private immutable dao;
    uint256 public immutable limit;

    constructor(INounsDAOV2 _dao, uint256 _limit) {
        dao = _dao;
        limit = _limit;
    }

    function check(address voter, uint256 proposalId, uint8 support, bytes calldata rule)
        external
        view
        override
        returns (bool)
    {
        (, uint256[] memory values,,) = dao.getActions(proposalId);
        uint256 total = 0;
        for (uint256 i = 0; i < values.length; i++) {
            total += values[i];
        }
        return total <= limit;
    }
}

contract NoUpgrades is IRule {
    INounsDAOV2 private immutable dao;

    constructor(INounsDAOV2 _dao) {
        dao = _dao;
    }

    function check(address voter, uint256 proposalId, uint8 support, bytes calldata rule)
        external
        view
        override
        returns (bool)
    {
        (address[] memory targets,,,) = dao.getActions(proposalId);
        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i] == address(dao)) {
                return false;
            }
        }
        return true;
    }
}

contract AligatorOnchainAuthority {
    address public immutable owner;
    IGovernorBravo public immutable governor;

    mapping(address => address[]) public subDelegations; // from => to[]
    mapping(address => uint256) public canVote;

    event SubDelegation(address indexed from, address indexed to, bool indexed status);

    constructor(IGovernorBravo _governor) {
        owner = msg.sender;
        governor = _governor;
        canVote[msg.sender] = 1;
    }

    function castVote(uint256 proposalId, uint8 support) external {
        require(canVote[msg.sender] > 0);
        governor.castVote(proposalId, support);
    }

    function subDelegate(address account, bool status) external {
        require(canVote[msg.sender] > 0);

        if (status) {
            canVote[account] += 1;
            subDelegations[msg.sender].push(account);
        } else {
            undelegate(account);
        }
    }

    function undelegate(address account) internal {
        for (uint256 i = 0; i < subDelegations[account].length; i++) {
            address to = subDelegations[account][i];
            undelegate(to);
            canVote[to]--;
        }
        delete subDelegations[account];
    }
}

// Simple delegation
// Q1: A -> B -> C, can A and B vote? Yes
// Q2: A -> B, A -> C, can both B and C vote? Yes

// Constraints
// Q3: A -> B (max 100e) -> C (7 days). C can only vote for 7 days and less than 100e
// Q4: Can it be multiple constraints? Yes. AND, OR, etc.? No
// Q5: Diamond: A -> B (max 100e), A -> C (7 days), B -> D, C -> D. D can only vote for 7 days OR less than 100e
// Q6: On-chain vs off-chain. Diamon scenario + constraints
