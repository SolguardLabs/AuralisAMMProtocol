import assert from "node:assert/strict";
import test from "node:test";

import { AuralisClient, deadline, minimumAmount } from "./AuralisClient.js";
import type { Address, ContractReadRequest, PoolHealth, PublicClient, SwapQuote } from "./types.js";

const FACTORY = "0x0000000000000000000000000000000000000010" as Address;
const LENS = "0x0000000000000000000000000000000000000020" as Address;
const MONITOR = "0x0000000000000000000000000000000000000030" as Address;
const TOKEN0 = "0x0000000000000000000000000000000000000040" as Address;
const TOKEN1 = "0x0000000000000000000000000000000000000050" as Address;
const POOL = "0x0000000000000000000000000000000000000060" as Address;
const RECIPIENT = "0x0000000000000000000000000000000000000070" as Address;

class MockPublicClient implements PublicClient {
  readonly calls: ContractReadRequest[] = [];
  readonly responses = new Map<string, unknown>();

  async readContract<T>(request: ContractReadRequest): Promise<T> {
    this.calls.push(request);
    if (!this.responses.has(request.functionName)) {
      throw new Error(`Missing response for ${request.functionName}`);
    }
    return this.responses.get(request.functionName) as T;
  }
}

function createClient(publicClient: MockPublicClient): AuralisClient {
  return new AuralisClient(publicClient, {
    factory: FACTORY,
    lens: LENS,
    healthMonitor: MONITOR,
  });
}

test("resolves canonical pools and normalizes the zero address", async () => {
  const publicClient = new MockPublicClient();
  const client = createClient(publicClient);
  publicClient.responses.set("getPool", POOL);

  assert.equal(await client.poolFor(TOKEN0, TOKEN1), POOL);
  assert.equal(publicClient.calls[0]?.address, FACTORY);

  publicClient.responses.set("getPool", "0x0000000000000000000000000000000000000000");
  assert.equal(await client.poolFor(TOKEN0, TOKEN1), null);
});

test("returns typed swap quotes through the lens", async () => {
  const publicClient = new MockPublicClient();
  const client = createClient(publicClient);
  const quote: SwapQuote = {
    tokenIn: TOKEN0,
    tokenOut: TOKEN1,
    amountIn: 1_000n,
    netAmountIn: 997n,
    amountOut: 950n,
    lpFee: 2n,
    protocolFee: 1n,
    feePpm: 3_000,
    projectedReserve0: 10_997n,
    projectedReserve1: 9_050n,
    projectedImbalancePpm: 97_112n,
  };
  publicClient.responses.set("quoteSwap", quote);

  assert.deepEqual(await client.quoteSwap(POOL, TOKEN0, 1_000n), quote);
  assert.equal(publicClient.calls[0]?.address, LENS);
});

test("reads operational health through the monitor", async () => {
  const publicClient = new MockPublicClient();
  const client = createClient(publicClient);
  const health = { pool: POOL, flags: 0n, healthy: true } as PoolHealth;
  publicClient.responses.set("inspect", health);

  assert.deepEqual(await client.health(POOL), health);
  assert.equal(publicClient.calls[0]?.address, MONITOR);
});

test("derives deterministic slippage and deadline bounds", () => {
  assert.equal(minimumAmount(1_000_000n, 50), 995_000n);
  assert.equal(minimumAmount(1_000_000n, 0), 1_000_000n);
  assert.equal(deadline(300, 1_700_000_000), 1_700_000_300n);
  assert.throws(() => minimumAmount(1n, 10_000), RangeError);
  assert.throws(() => deadline(0, 1), RangeError);
});

test("builds router-ready swap requests from a quote", () => {
  const publicClient = new MockPublicClient();
  const client = createClient(publicClient);
  const quote = {
    tokenIn: TOKEN0,
    tokenOut: TOKEN1,
    amountIn: 1_000n,
    amountOut: 950n,
  } as SwapQuote;

  assert.deepEqual(client.buildSwapRequest(POOL, quote, RECIPIENT, 100, 300, 1_700_000_000), {
    pool: POOL,
    tokenIn: TOKEN0,
    amountIn: 1_000n,
    minimumAmountOut: 940n,
    recipient: RECIPIENT,
    deadline: 1_700_000_300n,
  });
});

test("rejects malformed deployment addresses", () => {
  const publicClient = new MockPublicClient();
  assert.throws(
    () =>
      new AuralisClient(publicClient, {
        factory: "0x1234" as Address,
        lens: LENS,
        healthMonitor: MONITOR,
      }),
    TypeError,
  );
});
