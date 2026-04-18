// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title  IStrategy — surface of a single AgentVault strategy contract.
/// @notice Each strategy is deployed by the Vault (which is its factory)
///         and holds only its own slice of the asset. The AI agent
///         (delegate) performs external protocol actions through
///         `executeAction`; the vault moves funds in/out via `pushFunds`
///         and `pullFunds` during rebalancing and user deposits/withdrawals.
///
///         Access control is delegated to the Vault:
///         - onlyVault (hardcoded immutable VAULT address) — pushFunds, pullFunds
///         - onlyAdmin (Vault.hasRole(DEFAULT_ADMIN_ROLE)) — whitelist, configs,
///           value sources, approvals, delegate updates
///         - onlyDelegateOrAuthority — executeAction
interface IStrategy {
    // ─────────────────────────────────────────────────────────────────────────
    // Types
    // ─────────────────────────────────────────────────────────────────────────

    struct AllowedAction {
        bool allowed;
        uint16 recipientOffset;
    }

    struct ValueSource {
        address target;
        bytes data;
    }

    struct ActionConfig {
        address target;
        bytes data;
        uint16 amountOffset;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error ZeroAddress();
    error AlreadyInitialized();
    error NotInitialized();
    error NotVault(address caller);
    error NotAdmin(address caller);
    error NotDelegateNorAuthority(address caller);
    error DataTooShort(uint256 length);
    error ActionNotAllowed(address target, bytes4 selector);
    error ActionAlreadyAllowed();
    error ActionAlreadyDisallowed();
    error AntiTheft(address caller, uint256 balanceBefore, uint256 balanceAfter);
    error RecipientMustBeVault(address recipient);
    error TargetIsAsset();
    error TargetIsSelf();
    error TargetIsVault();
    error CallFailed(bytes returnData);
    error ValueSourceFailed(uint256 index);
    error ValueSourceIndexOutOfBounds(uint256 index);
    error AutoDeployFailed(bytes returnData);
    error AutoWithdrawFailed(bytes returnData);
    error NotAdminNorDelegate(address caller);
    error SpenderNotTrusted(address spender);
    /// @dev Agent-driven paths (executeAction, approveToken) revert once
    ///      the parent Vault has reached its target-date deadline.
    error VaultMatured(uint256 deadline);

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event StrategyInitialized(address indexed vault, address indexed asset, address indexed delegate);
    event DelegateUpdated(address indexed oldDelegate, address indexed newDelegate);

    event AllowedActionAdded(address indexed target, bytes4 indexed selector, uint16 recipientOffset);
    event AllowedActionRemoved(address indexed target, bytes4 indexed selector);
    event ActionExecuted(address indexed target, bytes4 indexed selector, bytes32 dataHash);

    event ValueSourceAdded(uint256 index, address target);
    event ValueSourceRemoved(uint256 index);

    event DepositConfigSet(address target);
    event WithdrawConfigSet(address target);
    event DepositConfigRemoved();
    event WithdrawConfigRemoved();

    event FundsPushed(uint256 amount);
    event FundsPulled(uint256 requested, uint256 actual);

    event TokenApproved(address indexed token, address indexed spender, uint256 amount, address indexed caller);
    event TrustedSpenderSet(address indexed spender, bool trusted);

    // ─────────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────────

    function vault() external view returns (address);
    function asset() external view returns (IERC20);
    function delegate() external view returns (address);
    function initialized() external view returns (bool);

    // ─────────────────────────────────────────────────────────────────────────
    // Initializer (Clones pattern)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice One-shot initializer called by the Vault immediately after
    ///         cloning this contract. Cannot be called twice. The
    ///         implementation contract itself is locked at construction.
    function initialize(address vault_, IERC20 asset_, address delegate_) external;
    function actionCount() external view returns (uint64);

    /// @notice Total value of this strategy in asset units.
    ///         Returns idle balance + sum of value sources.
    function totalValue() external view returns (uint256);

    /// @notice Physical asset balance held directly by this strategy.
    function idleBalance() external view returns (uint256);

    /// @notice Sum of all registered value sources (excludes idle balance).
    function getExternalValue() external view returns (uint256);

    function valueSourceCount() external view returns (uint256);
    function allowedActions(address target, bytes4 selector) external view returns (bool allowed, uint16 recipientOffset);

    // ─────────────────────────────────────────────────────────────────────────
    // Admin (Vault.hasRole(DEFAULT_ADMIN_ROLE))
    // ─────────────────────────────────────────────────────────────────────────

    function setDelegate(address newDelegate) external;
    function addAllowedAction(address target, bytes4 selector, uint16 recipientOffset) external;
    function removeAllowedAction(address target, bytes4 selector) external;
    function setDepositConfig(address target, bytes calldata data, uint16 amountOffset) external;
    function setWithdrawConfig(address target, bytes calldata data, uint16 amountOffset) external;
    function removeDepositConfig() external;
    function removeWithdrawConfig() external;
    function addValueSource(address target, bytes calldata data) external;
    function removeValueSource(uint256 index) external;

    /// @notice ERC-20 approval from the strategy to a spender.
    /// @dev    Callable by EITHER the admin OR the strategy's delegate, but
    ///         the `spender` MUST be on the admin-curated trusted-spender
    ///         allowlist. Lets the agent set/bump allowances on a trusted
    ///         protocol (Aave V3 Pool, etc.) without round-tripping to the
    ///         admin, while the trust boundary stays under admin control.
    ///         Uses `forceApprove` so non-standard tokens (USDT) are safe.
    function approveToken(address token, address spender, uint256 amount) external;

    /// @notice Admin manages the trusted-spender allowlist consumed by
    ///         `approveToken`. Only addresses on this list can receive a
    ///         non-zero allowance from the strategy. Passing `trusted=false`
    ///         removes an entry (does NOT revoke an existing allowance —
    ///         call `approveToken(token, spender, 0)` for that).
    function setTrustedSpender(address spender, bool trusted) external;

    function trustedSpenders(address spender) external view returns (bool);

    // ─────────────────────────────────────────────────────────────────────────
    // Vault-only
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Receive `amount` of asset from the vault. Vault must have
    ///         transferred the tokens to this contract before calling.
    ///         If a deposit config is set, runs it to deploy the funds
    ///         into an external protocol.
    function pushFunds(uint256 amount) external;

    /// @notice Return up to `amount` of asset to the vault. If the strategy
    ///         has a withdraw config and insufficient idle, runs the config
    ///         to pull funds from an external protocol. Returns the actual
    ///         amount transferred (may be less than requested if the
    ///         strategy cannot liquidate enough).
    function pullFunds(uint256 amount) external returns (uint256 actual);

    // ─────────────────────────────────────────────────────────────────────────
    // Delegate or Authority
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Execute a whitelisted call from the strategy's context.
    /// @dev    Full validation chain: whitelist → target guards →
    ///         recipient check → anti-theft snapshot → call → anti-theft verify.
    function executeAction(address target, bytes calldata data) external returns (bytes memory result);
}
