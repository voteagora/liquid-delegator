# Agora Liquid Delegator

## Goal

Agora Liquid Delegator (codename Alligator) allows token holders to subdelegate all their votes to multiple people according to a set of rules. Any delegatee can further sub-delegate their votes to others, optionally adding even more rules.

For example, a token holder `0xAAA` delegates their votes to `0xBBB`, but only allows `0xBBB` use the tokens on proposals that move less than 100 ETH from the treasury. `0xBBB` sub-delegates their votes to `0xCCC`, but only allows voting in the last 12 hours before the vote closes. `0xCCC` can now use `0xAAA`'s voting power to cast a vote, but only on small proposals and only in the last 12 hours.

## Features

1. Sub-delegate to as any number of subjects
2. Add rules to sub-delegation:
   - Permissions: create proposal, vote, sign (via EIP-1271)
   - Limit number of re-delegations
   - Set timestamp range when sub-delegation is active
   - Limit voting to a number of blocks before vote closes
   - Custom rules (calls external contract to validate)
3. Casting votes, creating new proposals and voting on Prop House
4. Batched operations
5. Gas refund

### WORK IN PROGRESS

There's a few TODO items in the code and the tests are not comprehensive. But the repo is in good enough shape to ask for external feedback on the architecture & approach.

## How it works

Alligator is designed to work without holding user's tokens.

1. Alligator deploys a proxy contract for every user who wants to use the system. The proxy's address is deterministic and the proxy can be deployed by anyone. The proxy only allows commands from Alligator itself.
2. The user who wants to delegate their voting power via Alligator's system must first delegate (not transfer!) the original ERC20s to the corresponding Alligator's proxy.
3. The user can now configure sub-delegations. They can sub-delegate to any number of other users and can limit the sub-delegation to a set of specific rules.
4. The user who is delegated to can now vote by calling the corresponding function on Alligator. The user must include one or more delegation chains that they want to exercise.
5. The rules engine checks if the subdelegations are allowed, and forwards the request to vote to a proxy. The proxy casts a vote on Governor contract.

```
                        [2] ERC20
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

## Running tests:

1. Install [foundry](https://book.getfoundry.sh/getting-started/installation)
2. `forge test`

## Deploying to testnet:

1. Fund `0x77777101E31b4F3ECafF209704E947855eFbd014` with SepoliaETH
2. Get Etherscan API key
3. `forge script script/DeployAlligator.s.sol -vvvv --fork-url https://rpc-sepolia.rockx.com --chain-id 11155111 --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY`
