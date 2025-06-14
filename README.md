## UniSponge

UniSponge is a hook designed to mitigate impermanent loss (IL) by introducing a dynamic, volatility-based fee. When a significant price deviation is detected, UniSponge imposes an additional fee on swaps that push the price further away from the reference. Conversely, no extra fee is charged for swaps that reduce the deviation. This mechanism compensates liquidity providers for IL while preserving swap flexibility for users.


## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test --isolate -vv
```