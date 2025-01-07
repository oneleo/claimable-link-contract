## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Coverage

```shell
$ forge coverage --report summary --match-path 'test/*.t.sol' --no-match-coverage '(script/|test/)' | sed '/^[^|]/d' | sed '/^$/d'
```

### Deploy and verify

- Copy and modify the deployment variables with `cp .env.example .env`, then run the following command.
- The claimableLink contract address will be saved in `script/output/`.

```shell
$ chmod +x script/DeployClaimableLink.sh
$ script/DeployClaimableLink.sh
```
