// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

contract UniSponge is BaseHook {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    mapping(uint256 => uint160) internal _blockPrice;

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
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        if (_blockPrice[block.number] == 0) {
            (
                uint160 sqrtPriceX96,
                int24 tick,
                uint24 protocolFee,
                uint24 lpFee
            ) = poolManager.getSlot0(key.toId());
            _blockPrice[block.number] = sqrtPriceX96;
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
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());

        // pull some unspecified tokens from the swap as volatility fee
        int128 unspecifiedAmount;
        if (params.amountSpecified < 0 == params.zeroForOne) {
            // exactInput & zeroForOne
            // or
            // exactOutput & oneForZero
            // the unspecified token is token 1
            unspecifiedAmount =
                (swapDelta.amount1() * sqrtPriceX96) /
                _blockPrice[block.number];
        } else {
            // exactInput & oneForZero
            // or
            // exactOutput & zeroForOne
            // the unspecified token is token 0
            unspecifiedAmount =
                (swapDelta.amount0() * sqrtPriceX96) /
                _blockPrice[block.number];
        }

        // could donate back to pool
        return (this.afterSwap.selector, unspecifiedAmount);
    }
}
