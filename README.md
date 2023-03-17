# Agora Liquid Delegator

## Overview

Alligator allows token holders to delegate and subdelegate their voting power to _voters_ according to a set of rules. Any voter can further sub-delegate their voting power to others, optionally adding even more rules.

For example, a token holder `0xAAA` delegates their votes to `0xBBB`, but only allows `0xBBB` use the tokens on proposals that move less than 100 ETH from the treasury. `0xBBB` sub-delegates their votes to `0xCCC`, but only allows voting in the last 12 hours before the vote closes. `0xCCC` can now use `0xAAA`'s voting power to cast a vote, but only on small proposals and only in the last 12 hours.

This logic is achieved through the use of _proxy contracts_ designed to hold the voting power of their respective owner, and forward execution of governor's operations after subdelegation rules are validated by Alligator.

## Features

1. Create proxy contracts for an address
2. Sub-delegate to any number of voters
3. Add rules to sub-delegation:
   - Permissions: create proposal, vote, sign (via EIP-1271)
   - Limit number of re-delegations
   - Set timestamp range when sub-delegation is active
   - Limit voting to a number of blocks before vote closes
   - Custom rules (calls external contract to validate)
4. Casting votes, creating new proposals and voting on Prop House
5. Batch operations
6. Gas refund

## How it works

Alligator is designed to work without holding user's tokens.

1. Alligator deploys a proxy contract for every token holder who wants to use the system. The proxy's address is deterministic and the proxy can be deployed by anyone. The proxy only allows commands from Alligator itself.
2. The user who wants to delegate their voting power via Alligator's system must first delegate (not transfer!) the original tokens (ERC20s or ERC721s) to the corresponding Alligator's proxy.
3. The user can now configure sub-delegations. They can sub-delegate to any number of other users and can limit the sub-delegation to a set of specific rules.
4. The user who is delegated to can now vote by calling the corresponding function on Alligator. The user must include one or more delegation chains that they want to exercise.
5. The rules engine checks if the subdelegations are allowed, and forwards the request to vote to a proxy. The proxy casts a vote on Governor contract.

```
                        [2] VotingToken
      ┌ ─ ─ ─ ─ ─ ─ ─ ─ .delegateTo ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
                        (0xAAA's proxy)                  │
      │
╔══════════╗                                             │
║User 0xAAA║      ┌──────────────────┐                   ▼
╚══════════╝      │    Alligator     │         ┌──────────────────┐
      │           ├──────────────────┤   ┌────▶│  0xAAA's proxy   │───┐
[3] Alligator     │- Sub-delegations │   │     └──────────────────┘   │
.subDelegate─────▶│- Signatures      │   │     ┌──────────────────┐   │   ┌──────────────────┐
(0xBBB, {rules})  ├──────────────────┤ vote    │       ...        │ vote  │                  │
                  │┌────────────────┐│   │     └──────────────────┘   └──▶│     Governor     │
                  ││                ││   │     [1] Alligator              │                  │
[4] Alligator     ││     RULES      ││   │     deploys a proxy for        └──────────────────┘
.vote([0xAAA])────▶│     ENGINE     │├───┘     each user to a
      │           ││                ││         deterministic
      │           │└────────────────┘│         address via CREATE2
╔══════════╗      └──────────────────┘
║User 0xBBB║      [5] Check 0xAAA subdelegated
╚══════════╝      to 0xBBB and validate rules
```

### Authority chains

When a user votes via Alligator, they need to construct an authority chain off-chain and send it with their request (similar to Uniswap routing). This way Alligator can only store the essential information and pushes the complexity of finding the most benefitial chain.

The authority chain can be constructed by listening to on-chain subdelegation events and reconstructing graphs. It's possible there will be a few authority chains available to the same user with different constraints.

```
 SubDelegations:                       Authority Chains:
┌────────┬────────┬───────────────┐
│  FROM  │   TO   │     RULES     │    ┌───────┐   ┌───────┐   ┌───────┐
├────────┼────────┼───────────────┤    │ 0xAAA │──▶│ 0xBBB │──▶│ 0xCCC │
│ 0xAAA  │ 0xBBB  │   < 100 ETH   │    └───────┘   └───────┘   └───────┘
├────────┼────────┼───────────────┤
│ 0xBBB  │ 0xCCC  │   Last 12h    │    ┌───────┐   ┌───────┐
├────────┼────────┼───────────────┤    │ 0xFFF │──▶│ 0xCCC │
│ 0xFFF  │ 0xCCC  │Expires on 2023│    └───────┘   └───────┘
└────────┴────────┴───────────────┘
```

In the example above, the user `0xCCC` can use `0xAAA`'s and `0xFFF`'s voting powerby calling:

```
Alligator.castVotesWithReasonBatched([[0xAAA, 0xBBB, 0xCCC], [0xFFF, 0xCCC]], 1, 1, "");
```

From the Governor's perspective, it looks like users `0xAAA's proxy` and `0xFFF's proxy` are casting their votes.

```
╔══════════╗              ┌──────────────────┐         ┌──────────────────┐
║User 0xAAA║─ delegated ─▶│  0xAAA's proxy   │──vote──▶│                  │
╚══════════╝              └──────────────────┘         │     Governor     │
╔══════════╗              ┌──────────────────┐         │                  │
║User 0xFFF║─ delegated ─▶│  0xFFF's proxy   │──vote──▶│                  │
╚══════════╝              └──────────────────┘         └──────────────────┘
```

### Other design considerations

1. Should the rules be scoped to proxy or delegator? The initial prototype of Alligator used per-proxy rules, but we don't think in real life users want different sets of rules for different lots, and it's not how the original Governor works. E.g. if `0xAAA` subdelegates to `0xBBB`, we assume A trusts B (within the set rules) so if `0xCCC` delegates to `0xAAA`, `0xBBB` should be able to use these votes. It's also less on-chain storage and better scaling.

2. Should we support exclusive delegation? I.e. if `0xAAA` delegates to `0xBBB`, should `0xAAA` still be able to use that voting power? Supporting this would increase the complexity and raise many questions (e.g. if `0xCCC` delegates to `0xAAA`, can `0xAAA` still vote?). It could also easily be tricked by `0xAAA` via un-delegating, voting, and re-delegating back to `0xBBB`. So unless we introduce snapshots, adding exclusive delegation support doesn't give us much.

3. Is it possible to subdelegate a fraction of the tokens? According to our research, it's not possible unless we either hold users' tokens or change how the base token voting snapshots work. Alligator could theoretically used with something like [Franchiser](https://github.com/NoahZinsmeister/franchiser) (but we haven't tested this).

4. We are trying to make the contract as ergonomic as possible for the end users. Any friction will result in less actions taken, and we want more government participation. So ideally it should take the minimum number of transactions to set things up and use. For the setup, we need proxy deployment, delegate the original tokens and configure the rules. The proxy deployment is permissionless and can be done beforehand for big users. We can't get around the original token delegation transaction. Configuring the rules should be batched too. For voting, we want to have batched versions of castVote, offering a user to use different chains of authority to vote on a single proposal. We also offer a refund, if funds for it are available.

5. To limit EIP-1271 signatures to Prop House only, we are planning to do EIP-712 hashing on the contract side and check if the domain corresponds to the Prop House.

6. Should the base implementation of Alligator be upgradeable? Not sure, it adds marginal gas cost and security considerations. If we work on extending the feature set of Alligator, we can ask the users who want the extra features to re-delegate to Alligator v2, v3, etc.

## Running tests:

1. Install [foundry](https://book.getfoundry.sh/getting-started/installation)
2. `forge test`

## Deploying to testnet:

1. Configure `.env`
2. Run `forge script script/Deploy.s.sol -f goerli --broadcast --verify`

## Attack surface

Alligator does not hold user's tokens, so it's not possible to steal the tokens using a potential bug in the contract. However, it controls voting power which can be abused to vote on malicious proposals (e.g. transfer all the treasury tokens to evil.eth).

In such cases the contract owner holds the power to disable main operations (propose, vote, sign) via `OZ:Pausable` while a new version of Alligator is deployed. Users can then migrate to the new contracts.

# Alligator V2

![Alligator V2 architecture](/public/v2.png)

## Overview

AlligatorV2 has the same functionality of V1, with the addition of delegators being able to add their voting power into proxies owned by others, turning them effectively into _voting pools_.

This architecture is designed to prevent gas costs to grow uncontrollably in systems where the number of delegators to a single voter is significant. This is the case for most ecosystems using governors based on ERC20 tokens.

## Differences

**Proxy**

- In V1 each delegator had its own, single proxy. In V2 each address (voter) can be the _owner / controller_ of multiple pools
- In V1 delegators used to DELEGATE voting power to their own proxy, then SUBDELEGATE the proxy’s to others. In V2 delegators will mainly DELEGATE to pools owned by other _voters_
  - As a result delegators will be giving away their voting power to the chosen voter. They cannot use that voting power until they undelegate.
- Each proxy is now linked to a set of _base proxy rules_.
  - A voter owning a proxy cannot use the voting power held in the proxy unless the base rules are respected.
  - Anyone can create a proxy with rules for someone else. However incentives in this new system makes it so that delegators are incentivised to DELEGATE their voting power to existing pools instead of creating new ones.
  - In V2, the behaviour of a V1 proxy can be obtained with one having full permissions and no restrictions as rules, owned by delegator (instead of another voter)
- {Voter’s address} AND {Proxy base rules} are used to determine the address of a proxy.
  - There cannot be two pools owned by a voter with the same set of rules.

**Subdelegations**

- In V1 delegators could only have 1 proxy, thus subdelegations were both _address-specific_ (delegator→voter) and _proxy-specific_ (delegator’s proxy→voter). In V2 a voter may own multiple pools, so there is a distinction between the two. V2 allows both kinds of subdelegations:
  - Address-specific: SUBDELEGATE voting power of all pools owned by a voter to an address. This is also valid for pools yet to be created.
  - Proxy-specific: SUBDELEGATE voting power of a single proxy owned by a voter to an address
  - Proxy-specific subdelegation rules override address-specific ones.
- In V1 the delegator was the one who SUBDELEGATED voting power to others (retaining ability to vote). In V2 it’s the voters who SUBDELEGATE.
  - Voters are the proxy owners, and the first address in the authority chains when a governor operation is executed
- When a voter SUBDELEGATE to another voter, subdelegation rules stack on top of the original proxy’s base rules.

**Validation**

- Whenever a governor operation is executed (propose/vote/sign), the validation process first checks validity of base proxy rules and then additional subdelegation rules (based on the authority chain)
