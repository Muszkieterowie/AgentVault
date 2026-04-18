import { NextRequest, NextResponse } from "next/server";

const RPC_URLS: Record<string, string | undefined> = {
    "84532": process.env.NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL || process.env.NEXT_PUBLIC_LOCAL_RPC_URL,
};

const ALLOWED_METHODS = new Set([
    "eth_call",
    "eth_getBalance",
    "eth_getTransactionReceipt",
    "eth_getTransactionByHash",
    "eth_blockNumber",
    "eth_getBlockByNumber",
    "eth_getLogs",
    "eth_chainId",
    "eth_estimateGas",
    "eth_gasPrice",
    "eth_getCode",
    "eth_getStorageAt",
    "eth_getTransactionCount",
    "eth_sendRawTransaction",
    "net_version",
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

    if (!body.method || !ALLOWED_METHODS.has(body.method)) {
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
