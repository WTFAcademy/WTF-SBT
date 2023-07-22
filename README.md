# WTF-SBT
## About The Project
Soulbound Token (SBT) ERC1155 contracts used by WTF Academy for on-chain credentials.

## Features

- **Non-Transferable**: SoulBound, can not be transferred by users.
- **ERC1155**: WTF-SBT extends ERC1155, every SBT corresponds to an ERC1155 id.
- **Community Recovery**: at extreme condition (losing private key), community multisig (contract owner) can transfer the token to the new wallet under approval from the holder.

## Build

You can build the contracts with Foundry.

```shell
forge build
```

## Test

You can test the contracts with Foundry.

```shell
forge test
```
