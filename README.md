## UniSponge

UniSponge is a hook designed to mitigate impermanent loss (IL) by introducing a dynamic, volatility-based fee. When a significant price deviation is detected, UniSponge imposes an additional fee on swaps that push the price further away from the reference. Conversely, no extra fee is charged for swaps that reduce the deviation. This mechanism compensates liquidity providers for IL while preserving swap flexibility for users.


## Implementation

The calculation of volatility fee includes following params:
- `pivot price`
- `before swap price`
- `after swap price`

The `pivot price` is set to the pool’s current price at the time of the first swap in each block. It is also updated whenever the pool's liquidity changes. When a swap is executed, UniSponge records the price before and after the swap to measure the resulting price deviation.

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test --isolate -vv
```