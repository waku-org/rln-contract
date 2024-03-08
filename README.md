# Hardhat Project for rln-contract

## Requirements

The following will need to be installed in order to use this repo. Please follow the links and instructions.

- [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you've done it right if you can run `git --version`
- [Foundry / Foundryup](https://github.com/gakonst/foundry)
  - This will install `forge`, `cast`, and `anvil`
  - You can test you've installed them right by running `forge --version` and get an output like: `forge 0.2.0 (92f8951 2022-08-06T00:09:32.96582Z)`
  - To get the latest of each, just run `foundryup`
- [Yarn]
  - Classic version as per these instructions: https://classic.yarnpkg.com/lang/en/docs/install (tested with v1.22.21)
- [Nodejs]
  - Hardhat compatibility requires Nodejs < v18.19.1

## Compilation

```shell
forge install
yarn compile
```

## Testing with Hardhat

```shell
yarn test:hardhat
```

## Testing with Foundry

```shell
yarn test:foundry
```

## Deploying

### Locally

- To deploy on a local node, first start the local node and then run the deploy script

```shell
yarn node
yarn deploy:localhost
```

### Sepolia

- To deploy to an target network (like Sepolia), use the name as mentioned in the Hardhat config file.

```shell
yarn deploy:sepolia
# You may verify the contract using
yarn verify:sepolia # Ensure you have set ETHERSCAN_API_KEY in your env
```

## References

For more information, see https://hardhat.org/hardhat-runner/docs/guides/project-setup

## License

Dual-licensed under MIT or Apache 2.0, refer to [LICENSE-MIT](LICENSE-MIT) or [LICENSE-APACHE](LICENSE-APACHE) for more information.
