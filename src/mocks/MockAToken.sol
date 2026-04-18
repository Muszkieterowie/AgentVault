// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Rebasing-style aToken that wraps an underlying asset. Represents a
///         holder's share of the underlying pool: `balanceOf(a)` scales with
///         any new underlying that lands in this contract (e.g. from the
///         `YieldDripper`). Interface-compatible with what AgentVault / the
///         `StrategyTable` popover + `AaveV3LoopValue` need:
///          - ERC-20 surface (totalSupply, balanceOf, transfer, approve, etc.)
///          - only the pool can `mint` / `burn` via calls from
///            `MockAavePool.supply` / `.withdraw`.
contract MockAToken is IERC20 {
    using SafeERC20 for IERC20;

    string public name;
    string public symbol;
    uint8 public immutable decimals;
    IERC20 public immutable UNDERLYING_ASSET_ADDRESS;
    address public immutable POOL;

    uint256 private _totalShares;
    mapping(address => uint256) private _shares;
    mapping(address => mapping(address => uint256)) private _allowances;

    error NotPool();
    error InsufficientBalance();
    error InsufficientAllowance();

    modifier onlyPool() {
        if (msg.sender != POOL) revert NotPool();
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        IERC20 _underlying,
        address _pool
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        UNDERLYING_ASSET_ADDRESS = _underlying;
        POOL = _pool;
    }

    /// @dev Returns underlying balance held by this contract (the rebasing
    ///      pool). Grows over time as `YieldDripper.drip()` streams in.
    function totalSupply() public view returns (uint256) {
        return UNDERLYING_ASSET_ADDRESS.balanceOf(address(this));
    }

    function balanceOf(address account) public view returns (uint256) {
        uint256 total = _totalShares;
        if (total == 0) return 0;
        return (_shares[account] * totalSupply()) / total;
    }

    function totalShares() external view returns (uint256) {
        return _totalShares;
    }

    function sharesOf(address account) external view returns (uint256) {
        return _shares[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = _allowances[from][msg.sender];
        if (a != type(uint256).max) {
            if (a < amount) revert InsufficientAllowance();
            _allowances[from][msg.sender] = a - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        uint256 total = totalSupply();
        if (total == 0) revert InsufficientBalance();
        uint256 shares = (amount * _totalShares) / total;
        if (_shares[from] < shares) revert InsufficientBalance();
        _shares[from] -= shares;
        _shares[to] += shares;
        emit Transfer(from, to, amount);
    }

    /// @dev Called by the pool AFTER the underlying has already been
    ///      transferred in (the pool uses `safeTransferFrom(caller, aToken, amount)`).
    function mint(address to, uint256 amount) external onlyPool {
        // supply *before* this deposit
        uint256 supplyBefore = totalSupply() - amount;
        uint256 shares;
        if (_totalShares == 0 || supplyBefore == 0) {
            shares = amount;
        } else {
            shares = (amount * _totalShares) / supplyBefore;
        }
        _totalShares += shares;
        _shares[to] += shares;
        emit Transfer(address(0), to, amount);
    }

    /// @dev Called by the pool on withdraw. Burns shares worth `amount` of
    ///      underlying and forwards the underlying to `to`.
    function burn(address from, address to, uint256 amount) external onlyPool returns (uint256) {
        uint256 total = totalSupply();
        if (total == 0 || _totalShares == 0) revert InsufficientBalance();
        uint256 shares = (amount * _totalShares) / total;
        if (shares == 0 && amount > 0) shares = 1; // round up dust so balance can reach zero
        if (_shares[from] < shares) revert InsufficientBalance();
        _shares[from] -= shares;
        _totalShares -= shares;
        UNDERLYING_ASSET_ADDRESS.safeTransfer(to, amount);
        emit Transfer(from, address(0), amount);
        return amount;
    }
}
