export const StrategyABI = [
    // Delegate / Authority
    { type: "function", name: "executeAction", inputs: [{ name: "target", type: "address" }, { name: "data", type: "bytes" }], outputs: [{ name: "", type: "bytes" }], stateMutability: "nonpayable" },
    { type: "function", name: "setDelegate", inputs: [{ name: "newDelegate", type: "address" }], outputs: [], stateMutability: "nonpayable" },

    // Whitelist
    { type: "function", name: "addAllowedAction", inputs: [{ name: "target", type: "address" }, { name: "selector", type: "bytes4" }, { name: "recipientOffset", type: "uint256" }], outputs: [], stateMutability: "nonpayable" },
    { type: "function", name: "removeAllowedAction", inputs: [{ name: "target", type: "address" }, { name: "selector", type: "bytes4" }], outputs: [], stateMutability: "nonpayable" },

    // Deposit / Withdraw config
    { type: "function", name: "setDepositConfig", inputs: [{ name: "target", type: "address" }, { name: "data", type: "bytes" }], outputs: [], stateMutability: "nonpayable" },
    { type: "function", name: "setWithdrawConfig", inputs: [{ name: "target", type: "address" }, { name: "data", type: "bytes" }], outputs: [], stateMutability: "nonpayable" },
    { type: "function", name: "removeDepositConfig", inputs: [], outputs: [], stateMutability: "nonpayable" },
    { type: "function", name: "removeWithdrawConfig", inputs: [], outputs: [], stateMutability: "nonpayable" },

    // Value sources
    { type: "function", name: "addValueSource", inputs: [{ name: "target", type: "address" }, { name: "data", type: "bytes" }], outputs: [], stateMutability: "nonpayable" },
    { type: "function", name: "removeValueSource", inputs: [{ name: "index", type: "uint256" }], outputs: [], stateMutability: "nonpayable" },

    // Read
    { type: "function", name: "totalValue", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },
    { type: "function", name: "delegate", inputs: [], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
    { type: "function", name: "vault", inputs: [], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
    { type: "function", name: "asset", inputs: [], outputs: [{ name: "", type: "address" }], stateMutability: "view" },
    { type: "function", name: "depositConfig", inputs: [], outputs: [{ name: "target", type: "address" }, { name: "data", type: "bytes" }], stateMutability: "view" },
    { type: "function", name: "withdrawConfig", inputs: [], outputs: [{ name: "target", type: "address" }, { name: "data", type: "bytes" }], stateMutability: "view" },
    { type: "function", name: "valueSources", inputs: [{ name: "index", type: "uint256" }], outputs: [{ name: "target", type: "address" }, { name: "data", type: "bytes" }], stateMutability: "view" },
    { type: "function", name: "actionCount", inputs: [], outputs: [{ name: "", type: "uint256" }], stateMutability: "view" },

    // Events
    { type: "event", name: "ActionExecuted", inputs: [{ name: "target", type: "address", indexed: true }, { name: "selector", type: "bytes4", indexed: true }, { name: "caller", type: "address", indexed: true }] },
    { type: "event", name: "AllowedActionAdded", inputs: [{ name: "target", type: "address", indexed: true }, { name: "selector", type: "bytes4", indexed: false }, { name: "recipientOffset", type: "uint256", indexed: false }] },
    { type: "event", name: "AllowedActionRemoved", inputs: [{ name: "target", type: "address", indexed: true }, { name: "selector", type: "bytes4", indexed: false }] },
    { type: "event", name: "DelegateUpdated", inputs: [{ name: "oldDelegate", type: "address", indexed: false }, { name: "newDelegate", type: "address", indexed: false }] },
    { type: "event", name: "DepositConfigUpdated", inputs: [{ name: "target", type: "address", indexed: false }] },
    { type: "event", name: "WithdrawConfigUpdated", inputs: [{ name: "target", type: "address", indexed: false }] },
    { type: "event", name: "ValueSourceAdded", inputs: [{ name: "target", type: "address", indexed: false }, { name: "index", type: "uint256", indexed: false }] },
    { type: "event", name: "ValueSourceRemoved", inputs: [{ name: "index", type: "uint256", indexed: false }] },
] as const;
