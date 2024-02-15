# Opal contracts

## Deployment

```
/!\ You must have forge installed and a right configured .env
chmod 700 ./local_node.sh
./local_node.sh
```

The results are redirected to .anvil.env and look like this:

```
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
RPC_URL=http://localhost:8545
 GEM_ADDR=0xc3b99d27eF3B07C94Ee3cFD670281F0CF98A02f1
 PRICE_FEED_ADDR=0x20F5f006a0184883068bBF58fb0c526A8EEa8BFD
 BPT_ORACLE_ADDR=0x975cDd867aCB99f0195be09C269E2440aa1b1FA8
 OMNIPOOL_ADDR=0xd6096fbEd8bCc461d06b0C468C8b1cF7d45dC92d
 REWARD_MANAGER_ADDR=0x0aD6371dd7E9923d9968D63Eb8B9858c700abD9d
 GEM_WETH_BALANCER_POOL_ADDR=0xf5C157a51970752130Bf977601ad252323f7FC21
 VOTE_LOCKER_ADDR=0xa95A928eEc085801d981d13FFE749872D8FD5bec
 GAUGE_CONTROLLER_ADDR=0x575D3d18666B28680255a202fB5d482D1949bB32
 ESCROWED_TOKEN_ADDR=0x4458AcB1185aD869F982D51b5b0b87e23767A3A9
 MINTER_ESCROW_ADDR=0x8d375dE3D5DDde8d8caAaD6a4c31bD291756180b
 MINTER_ADDR=0x721a1ecB9105f2335a8EA7505D343a5a09803A06
 LIQUIDITY_GAUGE_ADDR=0x9852795dbb01913439f534b4984fBf74aC8AfA12
 GAUGE_FACTORY_ADDR=0x889D9A5AF83525a2275e41464FAECcCb3337fF60
```

## Tests

```
forge test
```

## Coverage

You need to install `lcov`

```
sudo apt-get install lcov
```

```
forge coverage --report lcov
genhtml ./lcov.info --output-directory ./coverage
```

## Omnipool

## Reward Manager

### Overview

The <strong>Reward Manager</strong> is a contract that manages the distribution of rewards obtained by omnipools. The reward share a user obtains depends on his share of the omnipool's LP.

Each time a user wishes to retrieve his rewards, the reward manager <strong>updates the omnipool's state</strong> and the <strong>user's state</strong>, then calculates the quantity of tokens to be distributed.

- <strong>Omnipool's state</strong> -
  Updating the omnipool status means claiming all the rewards available on its underlying pools. At this stage, if necessary, we can also swap extra reward tokens to gems tokens.

- <strong>User's state</strong> -
  Updating the user's status means calculating the amount of reward he is entitled to, based on the amount of reward obtained over a given period and his share of the LP.

### Concerns

Updating the omnipool's costs a lot of gas, as it involves swaps and claims for each underlying pool. However, this action is required for every user claim, so we could imagine a system that would limit the amount of calls.

If we could predict the amount of reward available for an omnipool, we wouldn't have to claim rewards from underlying pools every time a user wanted to claim his rewards. We could imagine a system where we have information on the theoretical amount of rewards available to the omnipool after it has claimed on all its underlying pools, as well as the quantity of rewards available to it because it has already claimed them. In this way, it is very likely that when a user wishes to retrieve his rewards, they are already available.
This approach would be highly efficient in terms of gas savings, as a user would not have to pay for the execution of claims on each underlying pool.

However, it raises enormous technical challenges.

- The first concerns underlying pools: how to predict the amount of reward obtained before the claim is made?
- The second, and probably the most complex, is that extra rewards are swapped for GEM tokens, so the quantity of GEM in reward depends directly on the price of the latter, which varies over time.

Under the current system, the quantity of GEM obtained is bound to increase, since the quantity held by the reward manager is fixed.
With this second principle, it's not GEM tokens that are stored, but their equivalent in extra reward tokens. This means that the user is exposed to price variations.

Note: If a system were in place to automatically update the omnipool's state on a daily basis, we could probably overlook this price variation on the GEM token.
But this would introduce a new difficulty, that of designing an automatic, self-powered module for this purpose.

### Technical documentation

- <strong>External functions</strong>
  - `claimEarnings`: Called by the user to claim its rewards. This method is in charge of updating the user state.
  - `setExtraRewardTokens`
