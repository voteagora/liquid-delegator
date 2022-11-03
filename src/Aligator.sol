// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IGovernorBravo} from "./interfaces/IGovernorBravo.sol";

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

contract AligatorOffchainAuthority {
    address public immutable owner;
    IGovernorBravo public immutable governor;
    mapping(address => mapping(address => bool)) public subDelegations;

    event SubDelegation(address indexed from, address indexed to, bool indexed status);

    constructor(IGovernorBravo _governor) {
        owner = msg.sender;
        governor = _governor;
    }

    function castVote(address[] calldata authority, uint256 proposalId, uint8 support) external {
        require(canVote(authority));
        governor.castVote(proposalId, support);
    }

    function subDelegate(address account, bool status) external {
        subDelegations[msg.sender][account] = status;
        emit SubDelegation(msg.sender, account, status);
    }

    function canVote(address[] calldata authority) internal view returns (bool) {
        address account = owner;
        for (uint256 i = 0; i < authority.length; i++) {
            address to = authority[i];
            if (!subDelegations[account][to]) {
                return false;
            }
            to = account;
        }

        return account == msg.sender;
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
