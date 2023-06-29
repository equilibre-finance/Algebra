// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import './AlgebraPoolBase.sol';
import '../libraries/LiquidityMath.sol';
import '../libraries/TickManagement.sol';

/// @title Algebra positions abstract contract
/// @notice Contains the logic of recalculation and change of liquidity positions
abstract contract Positions is AlgebraPoolBase {
  using TickManagement for mapping(int24 => TickManagement.Tick);

  struct Position {
    uint256 liquidity; // The amount of liquidity concentrated in the range
    uint256 innerFeeGrowth0Token; // The last updated fee growth per unit of liquidity
    uint256 innerFeeGrowth1Token;
    uint128 fees0; // The amount of token0 owed to a LP
    uint128 fees1; // The amount of token1 owed to a LP
  }

  /// @inheritdoc IAlgebraPoolState
  mapping(bytes32 => Position) public override positions;

  /**
   * @notice This function fetches certain position object
   * @param owner The address owing the position
   * @param bottomTick The position's bottom tick
   * @param topTick The position's top tick
   * @return position The Position object
   */
  function getOrCreatePosition(address owner, int24 bottomTick, int24 topTick) internal view returns (Position storage) {
    bytes32 key;
    assembly {
      key := or(shl(24, or(shl(24, owner), and(bottomTick, 0xFFFFFF))), and(topTick, 0xFFFFFF))
    }
    return positions[key];
  }

  struct UpdatePositionCache {
    uint160 price; // The square root of the current price in Q64.96 format
    int24 prevInitializedTick; // The previous initialized tick in linked list
  }

  /**
   * @dev Updates position's ticks and its fees
   * @return amount0 The abs amount of token0 that corresponds to liquidityDelta
   * @return amount1 The abs amount of token1 that corresponds to liquidityDelta
   */
  function _updatePositionTicksAndFees(
    Position storage position,
    int24 bottomTick,
    int24 topTick,
    int128 liquidityDelta
  ) internal returns (uint256 amount0, uint256 amount1) {
    // using memory cache to avoid "stack too deep" error
    UpdatePositionCache memory cache = UpdatePositionCache(globalState.price, globalState.prevInitializedTick); // TODO OPTIMIZE

    int24 currentTick = globalState.tick;

    bool toggledBottom;
    bool toggledTop;
    {
      // scope to prevent "stack too deep"
      (uint256 _totalFeeGrowth0Token, uint256 _totalFeeGrowth1Token) = (totalFeeGrowth0Token, totalFeeGrowth1Token);
      if (liquidityDelta != 0) {
        toggledBottom = ticks.update(
          bottomTick,
          currentTick,
          liquidityDelta,
          _totalFeeGrowth0Token,
          _totalFeeGrowth1Token,
          false // isTopTick: false
        );

        toggledTop = ticks.update(
          topTick,
          currentTick,
          liquidityDelta,
          _totalFeeGrowth0Token,
          _totalFeeGrowth1Token,
          true // isTopTick: true
        );
      }

      (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = ticks.getInnerFeeGrowth(
        bottomTick,
        topTick,
        currentTick,
        _totalFeeGrowth0Token,
        _totalFeeGrowth1Token
      );

      _recalculatePosition(position, liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);
    }

    if (liquidityDelta != 0) {
      // if liquidityDelta is negative and the tick was toggled, it means that it should not be initialized anymore, so we delete it
      if (toggledBottom || toggledTop) {
        int24 previousTick = cache.prevInitializedTick;
        if (toggledBottom) {
          previousTick = _insertOrRemoveTick(bottomTick, currentTick, previousTick, liquidityDelta < 0);
        }
        if (toggledTop) {
          previousTick = _insertOrRemoveTick(topTick, currentTick, previousTick, liquidityDelta < 0);
        }
        if (cache.prevInitializedTick != previousTick) {
          globalState.prevInitializedTick = previousTick;
        }
      }

      int128 globalLiquidityDelta;
      (amount0, amount1, globalLiquidityDelta) = LiquidityMath.getAmountsForLiquidity(bottomTick, topTick, liquidityDelta, currentTick, cache.price);
      if (globalLiquidityDelta != 0) {
        uint128 liquidityBefore = liquidity;
        liquidity = LiquidityMath.addDelta(liquidityBefore, liquidityDelta);
      }
    }
  }

  /**
   * @notice Increases amounts of tokens owed to owner of the position
   * @param position The position object to operate with
   * @param liquidityDelta The amount on which to increase\decrease the liquidity
   * @param innerFeeGrowth0Token Total fee token0 fee growth per 1/liquidity between position's lower and upper ticks
   * @param innerFeeGrowth1Token Total fee token1 fee growth per 1/liquidity between position's lower and upper ticks
   */
  function _recalculatePosition(
    Position storage position,
    int128 liquidityDelta,
    uint256 innerFeeGrowth0Token,
    uint256 innerFeeGrowth1Token
  ) internal {
    uint128 liquidityBefore = uint128(position.liquidity);

    if (liquidityDelta == 0) {
      if (liquidityBefore == 0) return; // Do not recalculate the empty ranges
    } else {
      // change position liquidity
      position.liquidity = LiquidityMath.addDelta(liquidityBefore, liquidityDelta);
    }

    unchecked {
      // update the position
      uint256 _innerFeeGrowth0Token;
      uint128 fees0;
      if ((_innerFeeGrowth0Token = position.innerFeeGrowth0Token) != innerFeeGrowth0Token) {
        position.innerFeeGrowth0Token = innerFeeGrowth0Token;
        fees0 = uint128(FullMath.mulDiv(innerFeeGrowth0Token - _innerFeeGrowth0Token, liquidityBefore, Constants.Q128));
      }
      uint256 _innerFeeGrowth1Token;
      uint128 fees1;
      if ((_innerFeeGrowth1Token = position.innerFeeGrowth1Token) != innerFeeGrowth1Token) {
        position.innerFeeGrowth1Token = innerFeeGrowth1Token;
        fees1 = uint128(FullMath.mulDiv(innerFeeGrowth1Token - _innerFeeGrowth1Token, liquidityBefore, Constants.Q128));
      }

      // To avoid overflow owner has to collect fee before it
      if (fees0 | fees1 != 0) {
        position.fees0 += fees0;
        position.fees1 += fees1;
      }
    }
  }
}
