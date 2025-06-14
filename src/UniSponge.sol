// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

contract UniSponge is BaseHook {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    mapping(PoolId => mapping(uint256 => uint160)) internal _pivotPrice;

    constructor(IPoolManager poolManager) BaseHook(poolManager) {}

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: true,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: true,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        // update the pivot price after modifying liquidity
        PoolId pid = key.toId();
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(pid);
        _pivotPrice[pid][block.number] = sqrtPriceX96;
        return (
            this.afterAddLiquidity.selector,
            BalanceDeltaLibrary.ZERO_DELTA
        );
    }

    function _afterRemoveLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        // update the pivot price after modifying liquidity
        PoolId pid = key.toId();
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(pid);
        _pivotPrice[pid][block.number] = sqrtPriceX96;
        return (
            this.afterRemoveLiquidity.selector,
            BalanceDeltaLibrary.ZERO_DELTA
        );
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId pid = key.toId();
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(pid);
        _updateBeforeSwapPrice(sqrtPriceX96);

        // update pivot price if it's the first swap per pool in the block
        if (_pivotPrice[pid][block.number] == 0) {
            _pivotPrice[pid][block.number] = sqrtPriceX96;
            _flagBlockFirstSwap();
        }

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta swapDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        PoolId pid = key.toId();
        if (_isBlockFirstSwap()) {
            // no extra fee for the first swap per pool in each block
            return (this.afterSwap.selector, 0);
        }

        uint160 pivotPriceX96 = _pivotPrice[pid][block.number];
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());
        uint160 beforeSwapPrice = _getBeforeSwapPrice();
        bool vfeeOnToken1 = (params.amountSpecified < 0) && (params.zeroForOne);
        int128 unspecifiedAmount;

        // if this swap pushed the price even further away from the pivot price
        if (
            (beforeSwapPrice > pivotPriceX96) ==
            (sqrtPriceX96 > beforeSwapPrice)
        ) {
            uint160 priceDiff = (sqrtPriceX96 > beforeSwapPrice)
                ? sqrtPriceX96 - beforeSwapPrice
                : beforeSwapPrice - sqrtPriceX96;
            if (vfeeOnToken1) {
                // the unspecified token is token 1
                unspecifiedAmount = SafeCast.toInt128(
                    (uint128(swapDelta.amount1()) * priceDiff) / pivotPriceX96
                );
                poolManager.donate(
                    key,
                    0,
                    uint256(uint128(unspecifiedAmount)),
                    bytes("")
                );
            } else {
                // the unspecified token is token 0
                unspecifiedAmount = SafeCast.toInt128(
                    (uint128(swapDelta.amount0()) * priceDiff) / pivotPriceX96
                );
                poolManager.donate(
                    key,
                    uint256(uint128(unspecifiedAmount)),
                    0,
                    bytes("")
                );
            }
        }
        return (this.afterSwap.selector, unspecifiedAmount);
    }

    function _updateBeforeSwapPrice(uint160 price) internal {
        assembly {
            tstore(1, price)
        }
    }

    function _getBeforeSwapPrice() internal view returns (uint160 price) {
        assembly {
            price := tload(1)
        }
    }

    function _flagBlockFirstSwap() internal {
        assembly {
            tstore(0, 1)
        }
    }

    function _isBlockFirstSwap() internal view returns (bool first) {
        assembly {
            first := tload(0)
        }
    }
}
