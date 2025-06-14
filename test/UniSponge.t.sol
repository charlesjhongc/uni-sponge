// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {UniSponge} from "../src/UniSponge.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {console} from "forge-std/console.sol";

contract UniSpongeTest is Test, Deployers {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;

    UniSponge hook;
    PoolKey key2;
    address user;

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        user = makeAddr("user");
        vm.label(user, "user");
        currency0.transfer(user, 1000 ether);
        currency1.transfer(user, 1000 ether);
        vm.startPrank(user);
        IERC20Minimal(Currency.unwrap(currency0)).approve(
            address(swapRouter),
            1000 ether
        );
        IERC20Minimal(Currency.unwrap(currency1)).approve(
            address(swapRouter),
            1000 ether
        );
        vm.stopPrank();

        address hookAddress = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.AFTER_SWAP_FLAG |
                    Hooks.AFTER_ADD_LIQUIDITY_FLAG |
                    Hooks.AFTER_REMOVE_LIQUIDITY_FLAG |
                    Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
            )
        );
        deployCodeTo("UniSponge.sol", abi.encode(manager), hookAddress);
        hook = UniSponge(hookAddress);

        (key, ) = initPool(currency0, currency1, hook, 3000, SQRT_PRICE_1_1);
        (key2, ) = initPool(
            currency0,
            currency1,
            IHooks(address(0)),
            3000,
            SQRT_PRICE_1_1
        );

        // Add some liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        modifyLiquidityRouter.modifyLiquidity(
            key2,
            ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
        // set a new block for further test cases
        vm.roll(block.number + 1);
    }

    function test_normal_pool() public {
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        uint256 balBefore0 = currency0.balanceOf(user);
        uint256 balBefore1 = currency1.balanceOf(user);

        vm.startPrank(user);
        swapRouter.swap(
            key2,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            settings,
            ZERO_BYTES
        );
        vm.stopPrank();
        assertEq(currency0.balanceOf(user), balBefore0 - 1 ether);
        assertGt(currency1.balanceOf(user), balBefore1);
        uint256 output1 = currency1.balanceOf(user) - balBefore1;
        console.log("[Without UniSponge] First swap output", output1);

        vm.startPrank(user);
        balBefore1 = currency1.balanceOf(user);
        swapRouter.swap(
            key2,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            settings,
            ZERO_BYTES
        );
        vm.stopPrank();
        output1 = currency1.balanceOf(user) - balBefore1;
        console.log("[Without UniSponge] Second swap output", output1);
    }

    function test_pool_with_vFee_hook() public {
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        uint256 balBefore0 = currency0.balanceOf(user);
        uint256 balBefore1 = currency1.balanceOf(user);

        vm.startPrank(user);
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            settings,
            ZERO_BYTES
        );
        vm.stopPrank();
        assertEq(currency0.balanceOf(user), balBefore0 - 1 ether);
        assertGt(currency1.balanceOf(user), balBefore1);
        uint256 output1 = currency1.balanceOf(user) - balBefore1;
        console.log("[With UniSponge] First swap output", output1);

        balBefore1 = currency1.balanceOf(user);
        vm.startPrank(user);
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            settings,
            ZERO_BYTES
        );
        vm.stopPrank();
        output1 = currency1.balanceOf(user) - balBefore1;
        console.log("[With UniSponge] Second swap output", output1);
    }
}
