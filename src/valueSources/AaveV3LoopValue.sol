// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Minimal interface for Aave V3's price oracle. Returns asset prices
///      in a base-currency quote with `BASE_CURRENCY_UNIT` decimals (typically
///      USD with 8 decimals on Aave V3 mainnet deployments).
interface IAaveOracle {
    function getAssetPrice(address asset) external view returns (uint256);
}

/// @title  AaveV3LoopValue
/// @notice Net-value helper for Aave V3 leveraged-loop strategies.
///         Computes `collateralValue - debtValue` in debt-asset units and
///         returns it as a single `uint256` suitable for registration as a
///         Strategy value source.
///
///         Example:
///           Collateral: WETH (aWETH for balance reads, WETH for oracle)
///           Debt      : USDC (varDebtUSDC for balance reads, USDC for oracle)
///           The helper returns the strategy's net USDC-equivalent position.
///
/// @dev    Register on the strategy with:
///           strategy.addValueSource(
///               address(loopValueHelper),
///               abi.encodeCall(AaveV3LoopValue.valueOf, (address(strategy)))
///           );
///
///         One helper per (collateralUnderlying, debtUnderlying) pair; any
///         number of strategies can use the same helper by varying the
///         strategy address in the registered calldata.
contract AaveV3LoopValue {
    IAaveOracle public immutable ORACLE;

    /// @notice Underlying collateral asset used for oracle price lookup.
    address public immutable COLLATERAL_UNDERLYING;
    /// @notice aToken held by the strategy (reads collateral balance).
    address public immutable COLLATERAL_ATOKEN;
    /// @notice Decimals of the underlying collateral asset.
    uint8   public immutable COLLATERAL_DECIMALS;

    /// @notice Underlying debt asset used for oracle price lookup (also the
    ///         unit the returned value is expressed in).
    address public immutable DEBT_UNDERLYING;
    /// @notice Variable-debt token held by the strategy (reads debt balance).
    address public immutable DEBT_VARIABLE_TOKEN;
    /// @notice Decimals of the underlying debt asset (determines return unit).
    uint8   public immutable DEBT_DECIMALS;

    constructor(
        IAaveOracle oracle_,
        address collateralUnderlying,
        address collateralAToken,
        uint8   collateralDecimals,
        address debtUnderlying,
        address debtVariableToken,
        uint8   debtDecimals
    ) {
        ORACLE                = oracle_;
        COLLATERAL_UNDERLYING = collateralUnderlying;
        COLLATERAL_ATOKEN     = collateralAToken;
        COLLATERAL_DECIMALS   = collateralDecimals;
        DEBT_UNDERLYING       = debtUnderlying;
        DEBT_VARIABLE_TOKEN   = debtVariableToken;
        DEBT_DECIMALS         = debtDecimals;
    }

    /// @notice Net value of `strategy`'s Aave loop position in debt-asset units.
    /// @dev    Formula:
    ///           collateralInDebtUnits = collateralAmount * collateralPrice / debtPrice
    ///                                   / 10^(collateralDecimals - debtDecimals)
    ///           netValue              = max(0, collateralInDebtUnits - debtAmount)
    ///
    ///         Returns 0 when the position is underwater (debt > collateral).
    ///         This keeps `totalAssets` monotonic with respect to NAV reads
    ///         even in adverse conditions — callers see "no value" rather
    ///         than a revert.
    function valueOf(address strategy) external view returns (uint256) {
        uint256 collateralAmount = IERC20(COLLATERAL_ATOKEN).balanceOf(strategy);
        uint256 debtAmount       = IERC20(DEBT_VARIABLE_TOKEN).balanceOf(strategy);

        if (collateralAmount == 0) {
            return 0; // no collateral => no net value (debt is someone else's problem)
        }

        uint256 collateralPrice = ORACLE.getAssetPrice(COLLATERAL_UNDERLYING);
        uint256 debtPrice       = ORACLE.getAssetPrice(DEBT_UNDERLYING);
        require(debtPrice > 0, "zero debt price");

        // Convert collateral amount to debt-asset units, scaled by the
        // decimal difference between the two underlyings.
        uint256 collateralInDebtUnits;
        if (COLLATERAL_DECIMALS >= DEBT_DECIMALS) {
            uint256 scale = 10 ** (uint256(COLLATERAL_DECIMALS) - uint256(DEBT_DECIMALS));
            collateralInDebtUnits = (collateralAmount * collateralPrice) / (debtPrice * scale);
        } else {
            uint256 scale = 10 ** (uint256(DEBT_DECIMALS) - uint256(COLLATERAL_DECIMALS));
            collateralInDebtUnits = (collateralAmount * collateralPrice * scale) / debtPrice;
        }

        return collateralInDebtUnits > debtAmount ? collateralInDebtUnits - debtAmount : 0;
    }
}
