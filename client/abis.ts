const poolSnapshotComponents = [
  { name: "pool", type: "address" },
  { name: "token0", type: "address" },
  { name: "token1", type: "address" },
  { name: "grossReserve0", type: "uint256" },
  { name: "grossReserve1", type: "uint256" },
  { name: "activeReserve0", type: "uint256" },
  { name: "activeReserve1", type: "uint256" },
  { name: "pendingLPFee0", type: "uint256" },
  { name: "pendingLPFee1", type: "uint256" },
  { name: "protocolFee0", type: "uint256" },
  { name: "protocolFee1", type: "uint256" },
  { name: "totalSupply", type: "uint256" },
  { name: "spotPrice0X128", type: "uint256" },
  { name: "anchorRatioX128", type: "uint256" },
  { name: "imbalancePpm", type: "uint256" },
  { name: "blockTimestamp", type: "uint256" },
  { name: "paused", type: "bool" },
] as const;

const swapQuoteComponents = [
  { name: "tokenIn", type: "address" },
  { name: "tokenOut", type: "address" },
  { name: "amountIn", type: "uint256" },
  { name: "netAmountIn", type: "uint256" },
  { name: "amountOut", type: "uint256" },
  { name: "lpFee", type: "uint256" },
  { name: "protocolFee", type: "uint256" },
  { name: "feePpm", type: "uint24" },
  { name: "projectedReserve0", type: "uint256" },
  { name: "projectedReserve1", type: "uint256" },
  { name: "projectedImbalancePpm", type: "uint256" },
] as const;

const burnQuoteComponents = [
  { name: "amount0", type: "uint256" },
  { name: "amount1", type: "uint256" },
  { name: "principal0", type: "uint256" },
  { name: "principal1", type: "uint256" },
  { name: "realizedFee0", type: "uint256" },
  { name: "realizedFee1", type: "uint256" },
  { name: "closesPosition", type: "bool" },
] as const;

const poolHealthComponents = [
  { name: "pool", type: "address" },
  { name: "flags", type: "uint256" },
  { name: "physicalBalance0", type: "uint256" },
  { name: "physicalBalance1", type: "uint256" },
  { name: "grossReserve0", type: "uint256" },
  { name: "grossReserve1", type: "uint256" },
  { name: "activeReserve0", type: "uint256" },
  { name: "activeReserve1", type: "uint256" },
  { name: "obligations0", type: "uint256" },
  { name: "obligations1", type: "uint256" },
  { name: "imbalancePpm", type: "uint256" },
  { name: "oracleAge", type: "uint256" },
  { name: "healthy", type: "bool" },
] as const;

export const factoryAbi = [
  {
    type: "function",
    name: "getPool",
    stateMutability: "view",
    inputs: [
      { name: "tokenA", type: "address" },
      { name: "tokenB", type: "address" },
    ],
    outputs: [{ name: "pool", type: "address" }],
  },
] as const;

export const lensAbi = [
  {
    type: "function",
    name: "snapshot",
    stateMutability: "view",
    inputs: [{ name: "poolAddress", type: "address" }],
    outputs: [{ name: "state", type: "tuple", components: poolSnapshotComponents }],
  },
  {
    type: "function",
    name: "quoteSwap",
    stateMutability: "view",
    inputs: [
      { name: "poolAddress", type: "address" },
      { name: "tokenIn", type: "address" },
      { name: "amountIn", type: "uint256" },
    ],
    outputs: [{ name: "quote", type: "tuple", components: swapQuoteComponents }],
  },
  {
    type: "function",
    name: "quoteBurn",
    stateMutability: "view",
    inputs: [
      { name: "poolAddress", type: "address" },
      { name: "owner", type: "address" },
      { name: "liquidity", type: "uint256" },
    ],
    outputs: [{ name: "quote", type: "tuple", components: burnQuoteComponents }],
  },
] as const;

export const healthMonitorAbi = [
  {
    type: "function",
    name: "inspect",
    stateMutability: "view",
    inputs: [{ name: "poolAddress", type: "address" }],
    outputs: [{ name: "report", type: "tuple", components: poolHealthComponents }],
  },
] as const;
