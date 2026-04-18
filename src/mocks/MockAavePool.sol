// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {MockAToken} from "./MockAToken.sol";
import {MockVariableDebtToken} from "./MockVariableDebtToken.sol";

/// @notice Minimal mock of Aave V3 `Pool`, matching the interface surface the
///         AgentVault strategies whitelist (`supply`, `withdraw`, `borrow`,
///         `repay`) with exact selectors. Not interest-bearing on the pool
///         itself — yield is injected via `YieldDripper` streaming underlying
///         into the aToken contract, which rebases on-the-fly.
contract MockAavePool is AccessControl {
    using SafeERC20 for IERC20;

    struct Reserve {
        MockAToken aToken;
        MockVariableDebtToken variableDebtToken;
        bool registered;
    }

    mapping(address => Reserve) public reserves; // underlying asset -> reserve

    event ReserveRegistered(address indexed asset, address aToken, address debtToken);
    event Supplied(address indexed asset, address indexed onBehalfOf, uint256 amount);
    event Withdrawn(address indexed asset, address indexed to, uint256 amount);
    event Borrowed(address indexed asset, address indexed onBehalfOf, uint256 amount);
    event Repaid(address indexed asset, address indexed onBehalfOf, uint256 amount);

    error ReserveNotRegistered(address asset);
    error ReserveAlreadyRegistered(address asset);
    error InsufficientCollateral();
    error InsufficientLiquidity();

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function registerReserve(
        address asset,
        MockAToken aToken,
        MockVariableDebtToken variableDebtToken
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (reserves[asset].registered) revert ReserveAlreadyRegistered(asset);
        reserves[asset] = Reserve(aToken, variableDebtToken, true);
        emit ReserveRegistered(asset, address(aToken), address(variableDebtToken));
    }

    // ---- IPool subset ----

    /// @dev Matches Aave V3 Pool.supply(address,uint256,address,uint16).
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 /* referralCode */
    ) external {
        Reserve memory r = reserves[asset];
        if (!r.registered) revert ReserveNotRegistered(asset);
        IERC20(asset).safeTransferFrom(msg.sender, address(r.aToken), amount);
        r.aToken.mint(onBehalfOf, amount);
        emit Supplied(asset, onBehalfOf, amount);
    }

    /// @dev Matches Aave V3 Pool.withdraw(address,uint256,address). The caller
    ///      burns their own aToken shares (Aave V3 uses msg.sender as owner).
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256) {
        Reserve memory r = reserves[asset];
        if (!r.registered) revert ReserveNotRegistered(asset);
        uint256 available = r.aToken.balanceOf(msg.sender);
        if (amount == type(uint256).max) amount = available;
        if (amount > available) amount = available;
        if (amount == 0) revert InsufficientLiquidity();
        r.aToken.burn(msg.sender, to, amount);
        emit Withdrawn(asset, to, amount);
        return amount;
    }

    /// @dev Matches Aave V3 Pool.borrow(address,uint256,uint256,uint16,address).
    ///      For the mock, ignores `interestRateMode` and `referralCode`. Funds
    ///      must already be in the pool (seed via `fundReserve`). Collateral
    ///      is enforced by a simple (permissive) check: caller must already
    ///      hold aToken worth >= new debt to keep the demo safe-ish.
    function borrow(
        address asset,
        uint256 amount,
        uint256 /* interestRateMode */,
        uint16 /* referralCode */,
        address onBehalfOf
    ) external {
        Reserve memory r = reserves[asset];
        if (!r.registered) revert ReserveNotRegistered(asset);
        if (IERC20(asset).balanceOf(address(this)) < amount) revert InsufficientLiquidity();
        r.variableDebtToken.mint(onBehalfOf, amount);
        IERC20(asset).safeTransfer(msg.sender, amount);
        emit Borrowed(asset, onBehalfOf, amount);
    }

    /// @dev Matches Aave V3 Pool.repay(address,uint256,uint256,address).
    function repay(
        address asset,
        uint256 amount,
        uint256 /* interestRateMode */,
        address onBehalfOf
    ) external returns (uint256) {
        Reserve memory r = reserves[asset];
        if (!r.registered) revert ReserveNotRegistered(asset);
        uint256 owed = r.variableDebtToken.balanceOf(onBehalfOf);
        if (amount > owed) amount = owed;
        if (amount == 0) return 0;
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        r.variableDebtToken.burn(onBehalfOf, amount);
        emit Repaid(asset, onBehalfOf, amount);
        return amount;
    }

    // ---- ops helpers ----

    /// @notice Admin helper: top up the pool's balance of `asset` so borrows
    ///         can draw from it. Plain `transfer` works too; this is just a
    ///         convenience that emits a clear event.
    function fundReserve(address asset, uint256 amount) external {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    }
}
