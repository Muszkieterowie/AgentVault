// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MockAToken} from "./MockAToken.sol";

/// @notice Periodically drips pre-funded underlying into a `MockAToken` to
///         simulate yield accrual. Anyone can call `drip()` once per interval
///         (so a cheap cron / Chainlink-Automation / Gelato keeper can trigger
///         it). Funds remaining in the dripper are owner-withdrawable.
///
///         Example for USDC at 10 pct APY on a 100_000 USDC reserve, dripping
///         hourly: `dripAmount = 1.14 USDC` (`reserve * apy / (365*24)`).
contract YieldDripper is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable underlying;
    MockAToken public immutable aToken;
    uint256 public immutable interval;

    uint256 public dripAmount;
    uint256 public lastDrip;
    uint256 public totalDripped;

    event Dripped(uint256 amount, uint256 newATokenBalance, uint256 timestamp);
    event DripAmountSet(uint256 oldAmount, uint256 newAmount);

    error NotReady(uint256 readyAt);
    error NothingToDrip();

    constructor(
        IERC20 _underlying,
        MockAToken _aToken,
        uint256 _dripAmount,
        uint256 _interval,
        address _owner
    ) Ownable(_owner) {
        underlying = _underlying;
        aToken = _aToken;
        dripAmount = _dripAmount;
        interval = _interval;
        lastDrip = block.timestamp;
    }

    /// @notice Permissionless. Streams `dripAmount` (or whatever balance
    ///         remains, if smaller) of underlying into the aToken, which
    ///         rebases every holder up by that share.
    function drip() external returns (uint256 sent) {
        uint256 readyAt = lastDrip + interval;
        if (block.timestamp < readyAt) revert NotReady(readyAt);

        uint256 balance = underlying.balanceOf(address(this));
        if (balance == 0) revert NothingToDrip();
        sent = balance >= dripAmount ? dripAmount : balance;

        lastDrip = block.timestamp;
        totalDripped += sent;

        underlying.safeTransfer(address(aToken), sent);
        emit Dripped(sent, underlying.balanceOf(address(aToken)), block.timestamp);
    }

    function isReady() external view returns (bool) {
        return block.timestamp >= lastDrip + interval;
    }

    function timeUntilReady() external view returns (uint256) {
        uint256 readyAt = lastDrip + interval;
        return block.timestamp >= readyAt ? 0 : readyAt - block.timestamp;
    }

    /// @notice Owner can tweak the per-drip amount (e.g. simulate different APYs).
    function setDripAmount(uint256 newAmount) external onlyOwner {
        emit DripAmountSet(dripAmount, newAmount);
        dripAmount = newAmount;
    }

    /// @notice Rescue any remaining underlying.
    function withdraw(address to, uint256 amount) external onlyOwner {
        underlying.safeTransfer(to, amount);
    }
}
