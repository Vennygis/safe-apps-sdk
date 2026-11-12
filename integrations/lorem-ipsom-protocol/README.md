# Lorem Ipsom Protocol integration

This directory adds an isolated LIP Solidity package to the Safe Apps SDK monorepo. It does not modify Safe's existing SDK packages or imply endorsement by Safe.

## Contract package

See [contracts](./contracts) for the Foundry project and `LIPIdentityEngine.sol`.

### NFT model

- ERC-721 identity tokens; mint starts at level 5.
- XP is granted by the authorized protocol operator.
- The holder spends the current XP threshold to gain one level.
- The next XP threshold doubles after each level-up.
- Level 100 unlocks the transformation state and emits a transformation event.
- Every 500th level emits a trait milestone event.
- Traits are extensible definitions with type, slot, value, metadata URI, rarity tier, and minimum level.
- A holder equips one trait per slot, subject to its level requirement.
- Abilities are extensible definitions with metadata, minimum level, enabled status, and cooldown.
- Ability activation is recorded on-chain and cooldown-enforced. Actual game effects/rendering remain in the trusted game client/backend and should be verified separately.

### Existing product rules kept outside the contract

The following product/economic rules are not hardcoded into this contract because payment asset, settlement chain, and enforcement design have not been approved:

- $5 level-up purchase.
- $50 monthly subscription with 2x experience and a collaboration mint.
- $20 monthly side-edition cap of one per user.
- Referral reward of +2 levels and one month of 2x experience.
- Ten first-appearance editions and five variants where applicable.
- Physical print run of 100,000 per print edition; NFT mint supply is not capped by that print quantity.

These should be implemented as separately reviewed sale, subscription, referral, and edition modules after the payment and eligibility rules are finalized. Do not interpret a Notion entry or content hash as a mint, legal title, or enforceable royalty by itself.

## Build and test

Run from this directory:

```bash
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge build
forge test -vvv
```

## Safe App integration boundary

The Safe Apps SDK is the wallet-connection and transaction-proposal layer. A Safe App can read the connected chain/account and prepare a transaction to this contract; the Safe owners must review and execute it through Safe's normal authorization flow. This repository change does not bypass Safe confirmations or deploy the contract.

## Security and release gates

- Pin exact OpenZeppelin and Foundry dependency versions before release.
- Add fuzz and invariant tests for XP arithmetic, trait slot replacement, cooldown boundaries, transfer behavior, and authorization.
- Define operator key custody/rotation and a least-privilege game backend.
- Review metadata URI availability and content-addressing strategy.
- Audit the contract and test on a designated network before production use.
- Verify chain ID, genesis hash, RPC provenance, contract address, and deployment receipt.
- USD prices and subscription logic must be handled by a separately specified payment module; never accept a mnemonic/private key as a protocol secret or seed.
