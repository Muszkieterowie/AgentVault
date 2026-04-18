// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

/// @notice Non-transferable debt token used by `MockAavePool`. Tracks how much
///         a borrower owes. No interest accrual in the mock — `repay` must
///         match the minted amount.
contract MockVariableDebtToken {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    address public immutable POOL;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    error NotPool();
    error InsufficientDebt();
    error NonTransferable();

    modifier onlyPool() {
        if (msg.sender != POOL) revert NotPool();
        _;
    }

    constructor(string memory _name, string memory _symbol, uint8 _decimals, address _pool) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        POOL = _pool;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function mint(address to, uint256 amount) external onlyPool {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyPool {
        uint256 bal = _balances[from];
        if (bal < amount) revert InsufficientDebt();
        _balances[from] = bal - amount;
        _totalSupply -= amount;
        emit Burn(from, amount);
        emit Transfer(from, address(0), amount);
    }

    function transfer(address, uint256) external pure returns (bool) {
        revert NonTransferable();
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert NonTransferable();
    }

    function approve(address, uint256) external pure returns (bool) {
        revert NonTransferable();
    }
}
