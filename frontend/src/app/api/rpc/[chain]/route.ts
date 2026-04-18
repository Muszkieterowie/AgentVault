import { NextRequest, NextResponse } from "next/server";

const RPC_URLS: Record<string, string | undefined> = {
    "84532": process.env.NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL || process.env.NEXT_PUBLIC_LOCAL_RPC_URL,
};

// Accept any standard read-only or raw-tx JSON-RPC method. Wagmi/viem probe a
// broad set (eth_feeHistory, eth_maxPriorityFeePerGas, eth_getBlockByHash,
// web3_clientVersion, eth_newBlockFilter, …) depending on version and node
// detection; listing them all by hand kept drifting out of date. This regex
// allows the standard namespaces while still blocking anything weird.
const METHOD_PATTERN = /^(eth|net|web3)_[A-Za-z0-9_]+$/;

// Methods that can mutate wallet state or attempt local signing — must never
// be proxied from a browser. The server has no private key, but an upstream
// node that accidentally has one unlocked would be catastrophic.
const BLOCKED_METHODS = new Set([
    "eth_sign",
    "eth_signTransaction",
    "eth_signTypedData",
    "eth_signTypedData_v3",
    "eth_signTypedData_v4",
    "personal_sign",
    "personal_ecRecover",
    "eth_accounts",
    "eth_requestAccounts",
]);

export async function POST(
    request: NextRequest,
    { params }: { params: Promise<{ chain: string }> }
) {
    const { chain } = await params;
    const rpcUrl = RPC_URLS[chain];

    if (!rpcUrl) {
        return NextResponse.json(
            { error: "Unsupported chain" },
            { status: 400 }
        );
    }

    let body: { method?: string;[key: string]: unknown };
    try {
        body = await request.json();
    } catch {
        return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });
    }

    if (!body.method || !METHOD_PATTERN.test(body.method) || BLOCKED_METHODS.has(body.method)) {
        return NextResponse.json(
            { error: `Method not allowed: ${body.method}` },
            { status: 403 }
        );
    }

    const upstream = await fetch(rpcUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
    });

    const data = await upstream.json();
    return NextResponse.json(data);
}
