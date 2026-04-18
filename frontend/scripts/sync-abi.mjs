#!/usr/bin/env node
// Regenerates frontend/src/abi/*.ts from the Foundry build at ../out/.
// Run from the repo root or frontend/ — both are handled.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const frontendRoot = path.resolve(__dirname, "..");
const repoRoot = path.resolve(frontendRoot, "..");

const sources = {
  VaultABI:        { json: "out/Vault.sol/Vault.json",               file: "src/abi/Vault.ts" },
  StrategyABI:     { json: "out/Strategy.sol/Strategy.json",         file: "src/abi/Strategy.ts" },
  YieldDripperABI: { json: "out/YieldDripper.sol/YieldDripper.json", file: "src/abi/YieldDripper.ts" },
  MockAavePoolABI: { json: "out/MockAavePool.sol/MockAavePool.json", file: "src/abi/MockAavePool.ts" },
};

for (const [name, { json, file }] of Object.entries(sources)) {
  const src = path.join(repoRoot, json);
  const dst = path.join(frontendRoot, file);
  const { abi } = JSON.parse(fs.readFileSync(src, "utf8"));
  const content = `// Auto-generated from ${json} — do not edit by hand.\n// Regenerate with: node scripts/sync-abi.mjs\nexport const ${name} = ${JSON.stringify(abi, null, 2)} as const;\n`;
  fs.writeFileSync(dst, content);
  console.log(`wrote ${file} (${abi.length} entries)`);
}
