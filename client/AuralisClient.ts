import { factoryAbi, healthMonitorAbi, lensAbi } from "./abis.js";
import type {
  Address,
  BurnQuote,
  PoolHealth,
  PoolSnapshot,
  PublicClient,
  SwapQuote,
  SwapRequest,
} from "./types.js";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;
const BPS = 10_000n;

export interface AuralisDeployment {
  factory: Address;
  lens: Address;
  healthMonitor: Address;
}

export class AuralisClient {
  readonly #publicClient: PublicClient;
  readonly #deployment: AuralisDeployment;

  constructor(publicClient: PublicClient, deployment: AuralisDeployment) {
    this.#publicClient = publicClient;
    this.#deployment = {
      factory: assertAddress(deployment.factory),
      lens: assertAddress(deployment.lens),
      healthMonitor: assertAddress(deployment.healthMonitor),
    };
  }

  async poolFor(tokenA: Address, tokenB: Address): Promise<Address | null> {
    const pool = await this.#publicClient.readContract<Address>({
      address: this.#deployment.factory,
      abi: factoryAbi,
      functionName: "getPool",
      args: [assertAddress(tokenA), assertAddress(tokenB)],
    });
    return pool.toLowerCase() === ZERO_ADDRESS ? null : assertAddress(pool);
  }

  snapshot(pool: Address): Promise<PoolSnapshot> {
    return this.#publicClient.readContract<PoolSnapshot>({
      address: this.#deployment.lens,
      abi: lensAbi,
      functionName: "snapshot",
      args: [assertAddress(pool)],
    });
  }

  quoteSwap(pool: Address, tokenIn: Address, amountIn: bigint): Promise<SwapQuote> {
    assertPositive(amountIn, "amountIn");
    return this.#publicClient.readContract<SwapQuote>({
      address: this.#deployment.lens,
      abi: lensAbi,
      functionName: "quoteSwap",
      args: [assertAddress(pool), assertAddress(tokenIn), amountIn],
    });
  }

  quoteBurn(pool: Address, owner: Address, liquidity: bigint): Promise<BurnQuote> {
    assertPositive(liquidity, "liquidity");
    return this.#publicClient.readContract<BurnQuote>({
      address: this.#deployment.lens,
      abi: lensAbi,
      functionName: "quoteBurn",
      args: [assertAddress(pool), assertAddress(owner), liquidity],
    });
  }

  health(pool: Address): Promise<PoolHealth> {
    return this.#publicClient.readContract<PoolHealth>({
      address: this.#deployment.healthMonitor,
      abi: healthMonitorAbi,
      functionName: "inspect",
      args: [assertAddress(pool)],
    });
  }

  buildSwapRequest(
    pool: Address,
    quote: SwapQuote,
    recipient: Address,
    slippageBps: number,
    ttlSeconds: number,
    nowSeconds = Math.floor(Date.now() / 1_000),
  ): SwapRequest {
    return {
      pool: assertAddress(pool),
      tokenIn: quote.tokenIn,
      amountIn: quote.amountIn,
      minimumAmountOut: minimumAmount(quote.amountOut, slippageBps),
      recipient: assertAddress(recipient),
      deadline: deadline(ttlSeconds, nowSeconds),
    };
  }
}

export function minimumAmount(amount: bigint, slippageBps: number): bigint {
  assertPositive(amount, "amount");
  if (!Number.isInteger(slippageBps) || slippageBps < 0 || slippageBps >= Number(BPS)) {
    throw new RangeError("slippageBps must be an integer from 0 to 9,999");
  }
  return (amount * (BPS - BigInt(slippageBps))) / BPS;
}

export function deadline(ttlSeconds: number, nowSeconds = Math.floor(Date.now() / 1_000)): bigint {
  if (!Number.isSafeInteger(ttlSeconds) || ttlSeconds <= 0) {
    throw new RangeError("ttlSeconds must be a positive safe integer");
  }
  if (!Number.isSafeInteger(nowSeconds) || nowSeconds < 0) {
    throw new RangeError("nowSeconds must be a nonnegative safe integer");
  }
  return BigInt(nowSeconds + ttlSeconds);
}

function assertAddress(value: Address): Address {
  if (!/^0x[0-9a-fA-F]{40}$/.test(value)) throw new TypeError(`Invalid address: ${value}`);
  return value;
}

function assertPositive(value: bigint, name: string): void {
  if (value <= 0n) throw new RangeError(`${name} must be positive`);
}
