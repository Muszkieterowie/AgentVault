export const VaultABI = [
    // ERC-4626
    { type: "function", name: "deposit", inputs: [{ name: "assets", type: "uint256" }, { name: "receiver", type: "address" }], outputs: [{ name: "shares", type: "uint256" }], stateMutability: "nonpayable" },
    { type: "function", name: "mint", inputs: [{ name: "shares", type: "uint256" }, { name: "receiver", type: "address" }], outputs: [{ name: "assets", type: "uint256" }], stateMutability: "nonpayable" },
    { type: "function", name: "withdraw", inputs: [{ name: "assets", type: "uint256" }, { name: "receiver", type: "address" }, { name: "owner", type: "address" }], outputs: [{ name: "shares", type: "uint256" }], stateMutability: "nonpayable" },
    { type: "function", name: "redeem", inputs: [{ name: "shares", type: "uint256" }, { name: "receiver", type: "address" }, { name: "owner", type: "address" }], outputs: [{ name: "assets", type: "uint256" }], stateMutability: "nonpayable" },
    { type: "function", name: "totalAssets", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
    { type: "function", name: "totalSupply", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
    { type: "function", name: "balanceOf", inputs: [{ name: "account", type: "address" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
    { type: "function", name: "asset", inputs: [], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
    { type: "function", name: "convertToAssets", inputs: [{ name: "shares", type: "uint256" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
    { type: "function", name: "convertToShares", inputs: [{ name: "assets", type: "uint256" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
    { type: "function", name: "decimals", inputs: [], outputs: [{ name: "", type: "uint8" }], stateMutability: "view" },
    { type: "function", name: "name", inputs: [], outputs: [{ name: "", type: "string" }], stateMutability: "view" },
    { type: "function", name: "symbol", inputs: [], outputs: [{ name: "", type: "string" }], stateMutability: "view" },
    { type: "function", name: "maxDeposit", inputs: [{ name: "receiver", type: "address" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
    { type: "function", name: "maxWithdraw", inputs: [{ name: "owner", type: "address" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
    { type: "function", name: "previewDeposit", inputs: [{ name: "assets", type: "uint256" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
    { type: "function", name: "previewWithdraw", inputs: [{ name: "assets", type: "uint256" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },

    // Strategy management
    { type: "function", name: "createStrategy", inputs: [{ name: "delegate", type: "address" }], outputs: [{ name: "strategyId", type: "uint256" }], stateMutability: "nonpayable" },
    { type: "function", name: "setStrategyWeight", inputs: [{ name: "strategyId", type: "uint256" }, { name: "weight", type: "uint256" }], outputs: [], stateMutability: "nonpayable" },
    { type: "function", name: "deactivateStrategy", inputs: [{ name: "strategyId", type: "uint256" }], outputs: [], stateMutability: "nonpayable" },
    { type: "function", name: "rebalance", inputs: [{ name: "strategyId", type: "uint256" }, { name: "delta", type: "int256" }], outputs: [], stateMutability: "nonpayable" },
    { type: "function", name: "setAuthority", inputs: [{ name: "account", type: "address" }], outputs: [], stateMutability: "nonpayable" },
    { type: "function", name: "strategies", inputs: [{ name: "strategyId", type: "uint256" }], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
    { type: "function", name: "strategyWeights", inputs: [{ name: "strategyId", type: "uint256" }], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
    { type: "function", name: "strategyActive", inputs: [{ name: "strategyId", type: "uint256" }], outputs: [{ name: "", type: "bool" }], stateMutability: "view" },
    { type: "function", name: "strategyCount", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },

    // AccessControl
    { type: "function", name: "hasRole", inputs: [{ name: "role", type: "bytes32" }, { name: "account", type: "address" }], outputs: [{ name: "", type: "bool" }], stateMutability: "view" },
    { type: "function", name: "DEFAULT_ADMIN_ROLE", inputs: [], outputs: [{ name: "", type: "bytes32" }], stateMutability: "view" },
    { type: "function", name: "AUTHORITY_ROLE", inputs: [], outputs: [{ name: "", type: "bytes32" }], stateMutability: "view" },
    { type: "function", name: "grantRole", inputs: [{ name: "role", type: "bytes32" }, { name: "account", type: "address" }], outputs: [], stateMutability: "nonpayable" },
    { type: "function", name: "revokeRole", inputs: [{ name: "role", type: "bytes32" }, { name: "account", type: "address" }], outputs: [], stateMutability: "nonpayable" },

    // Events
    { type: "event", name: "Deposit", inputs: [{ name: "sender", type: "address", indexed: true }, { name: "owner", type: "address", indexed: true }, { name: "assets", type: "uint256", indexed: false }, { name: "shares", type: "uint256", indexed: false }] },
    { type: "event", name: "Withdraw", inputs: [{ name: "sender", type: "address", indexed: true }, { name: "receiver", type: "address", indexed: true }, { name: "owner", type: "address", indexed: true }, { name: "assets", type: "uint256", indexed: false }, { name: "shares", type: "uint256", indexed: false }] },
    { type: "event", name: "StrategyCreated", inputs: [{ name: "strategyId", type: "uint256", indexed: true }, { name: "strategy", type: "address", indexed: false }, { name: "delegate", type: "address", indexed: false }] },
    { type: "event", name: "StrategyWeightUpdated", inputs: [{ name: "strategyId", type: "uint256", indexed: true }, { name: "weight", type: "uint256", indexed: false }] },
    { type: "event", name: "StrategyDeactivated", inputs: [{ name: "strategyId", type: "uint256", indexed: true }] },
    { type: "event", name: "Rebalanced", inputs: [{ name: "strategyId", type: "uint256", indexed: true }, { name: "delta", type: "int256", indexed: false }] },
] as const;
