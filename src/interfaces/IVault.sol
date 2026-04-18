// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

/// @title  IVault — factory, router, and NAV surface of the AgentVault.
/// @notice The vault is a target-date ERC-4626 that:
///         - mints/burns shares in exchange for the underlying asset
///         - is the factory that deploys Strategy contracts
///         - rebalances funds between idle and strategies based on weights
///         - proxies Access-Control checks for all strategy contracts
///         - has a fixed **deadline**: deposits are only accepted before
///           it, withdrawals are only permitted from it onward. The fund
///           accumulates yield until the deadline, then depositors redeem
///           their pro-rata share for event-specific expenses.
interface IVault {
    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error ZeroAddress();
    error StrategyDoesNotExist(uint256 strategyId);
    error StrategyInactive(uint256 strategyId);
    error StrategyAlreadyDeactivated(uint256 strategyId);
    error StrategyStillHoldsFunds(uint256 strategyId, uint256 remaining);
    error WeightTooHigh(uint16 weightBps);
    error InsufficientIdle(uint256 requested, uint256 available);
    error InsufficientLiquidity(uint256 requested, uint256 available);

    /// @dev Deposit/mint attempted after the vault reached maturity.
    error VaultMatured(uint256 deadline);
    /// @dev Withdraw/redeem attempted before the vault reached maturity.
    error VaultNotMatured(uint256 deadline);
    /// @dev Constructor refused a deadline that was already in the past.
    error DeadlineInPast(uint256 deadline, uint256 nowTs);

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event VaultInitialized(
        address indexed asset,
        address indexed admin,
        address indexed authority,
        uint256 deadline
    );
    event AuthoritySet(address indexed oldAuthority, address indexed newAuthority);

    event StrategyCreated(uint256 indexed strategyId, address indexed strategy, address indexed delegate);
    event StrategyWeightSet(uint256 indexed strategyId, uint16 oldWeightBps, uint16 newWeightBps);
    event StrategyDeactivated(uint256 indexed strategyId);

    event Rebalanced(uint256 indexed strategyId, int256 delta, uint256 actual);
    event StrategiesDrained(uint256 totalPulled);

    // ─────────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────────

    function authority() external view returns (address);
    function strategyCount() external view returns (uint256);
    function strategies(uint256 strategyId) external view returns (address);
    function strategyWeights(uint256 strategyId) external view returns (uint16);
    function strategyActive(uint256 strategyId) external view returns (bool);

    /// @notice Unix timestamp at which the vault stops accepting deposits
    ///         and starts allowing withdrawals. Set once in the constructor.
    function DEADLINE() external view returns (uint256);

    /// @notice True iff `block.timestamp >= DEADLINE`. Convenience helper
    ///         for UIs that don't want to read block.timestamp themselves.
    function isMatured() external view returns (bool);

    // ─────────────────────────────────────────────────────────────────────────
    // Roles
    // ─────────────────────────────────────────────────────────────────────────

    function setAuthority(address newAuthority) external;

    // ─────────────────────────────────────────────────────────────────────────
    // Factory + registry
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Deploy a new Strategy contract and register it.
    /// @return strategyId      id in the registry (monotonic)
    /// @return strategyAddress deployed Strategy contract address
    function createStrategy(address delegate) external returns (uint256 strategyId, address strategyAddress);

    function setStrategyWeight(uint256 strategyId, uint16 weightBps) external;
    function deactivateStrategy(uint256 strategyId) external;

    // ─────────────────────────────────────────────────────────────────────────
    // Manual rebalancing (authority only)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Move funds between the vault's idle balance and a strategy.
    ///         Positive delta: push `delta` of asset from idle to strategy
    ///         (and let the strategy auto-deploy if it has a deposit config).
    ///         Negative delta: pull up to `-delta` of asset from strategy
    ///         back to idle (running the strategy's withdraw config if set).
    /// @return actual The actual amount moved (may be less than |delta| for
    ///                negative-delta pulls if the strategy can't liquidate
    ///                the full amount).
    function rebalance(uint256 strategyId, int256 delta) external returns (uint256 actual);

    /// @notice Pull every active strategy's full balance back to the vault.
    ///         Permissionless once the vault has matured — lets any user
    ///         (including the first to redeem) force the event-target to
    ///         be realized: funds leave protocols and land in the vault's
    ///         idle balance, ready for redemption.
    /// @return totalPulled Sum of asset returned from all strategies.
    function drainAllStrategies() external returns (uint256 totalPulled);
}
