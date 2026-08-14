export type Address = `0x${string}`;

export interface ContractReadRequest {
  address: Address;
  abi: readonly unknown[];
  functionName: string;
  args?: readonly unknown[];
}

export interface PublicClient {
  readContract<T>(request: ContractReadRequest): Promise<T>;
}

export interface PoolSnapshot {
  pool: Address;
  token0: Address;
  token1: Address;
  grossReserve0: bigint;
  grossReserve1: bigint;
  activeReserve0: bigint;
  activeReserve1: bigint;
  pendingLPFee0: bigint;
  pendingLPFee1: bigint;
  protocolFee0: bigint;
  protocolFee1: bigint;
  totalSupply: bigint;
  spotPrice0X128: bigint;
  anchorRatioX128: bigint;
  imbalancePpm: bigint;
  blockTimestamp: bigint;
  paused: boolean;
}

export interface SwapQuote {
  tokenIn: Address;
  tokenOut: Address;
  amountIn: bigint;
  netAmountIn: bigint;
  amountOut: bigint;
  lpFee: bigint;
  protocolFee: bigint;
  feePpm: number;
  projectedReserve0: bigint;
  projectedReserve1: bigint;
  projectedImbalancePpm: bigint;
}

export interface BurnQuote {
  amount0: bigint;
  amount1: bigint;
  principal0: bigint;
  principal1: bigint;
  realizedFee0: bigint;
  realizedFee1: bigint;
  closesPosition: boolean;
}

export interface PoolHealth {
  pool: Address;
  flags: bigint;
  physicalBalance0: bigint;
  physicalBalance1: bigint;
  grossReserve0: bigint;
  grossReserve1: bigint;
  activeReserve0: bigint;
  activeReserve1: bigint;
  obligations0: bigint;
  obligations1: bigint;
  imbalancePpm: bigint;
  oracleAge: bigint;
  healthy: boolean;
}

export interface SwapRequest {
  pool: Address;
  tokenIn: Address;
  amountIn: bigint;
  minimumAmountOut: bigint;
  recipient: Address;
  deadline: bigint;
}
