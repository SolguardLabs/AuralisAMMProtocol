# Integración

## Principios

Una integración debe separar cuatro momentos:

1. Descubrimiento de un pool canónico.
2. Lectura de estado y riesgo.
3. Cotización con un bloque de referencia.
4. Ejecución con límites propios y deadline.

Una cotización no reserva liquidez ni garantiza el estado futuro. El usuario debe proporcionar
los mínimos de salida y asumir que una transacción puede revertir si cambia el pool.

## Descubrir un pool

```solidity
address pool = factory.getPool(tokenA, tokenB);
if (pool == address(0)) revert PoolUnavailable();
```

No aceptes una dirección de pool aportada por una fuente externa sin comprobarla contra la
factory. Router, lens y monitor ya realizan esta validación.

## Snapshot

`AuralisPoolLens.snapshot(pool)` devuelve en una sola llamada:

- activos y reservas brutas;
- reservas activas y obligaciones de fee;
- supply de shares;
- precio spot Q128 y ratio ancla;
- desbalance, pausa y timestamp de lectura.

Ejemplo con el cliente:

```ts
const state = await auralis.snapshot(pool);

if (state.paused) {
  throw new Error("Pool operations are paused");
}

const reserveIdentity = state.activeReserve0 + state.pendingLPFee0 + state.protocolFee0;

if (reserveIdentity !== state.grossReserve0) {
  throw new Error("Reserve reconciliation failed");
}
```

## Cotizar un swap

```ts
const quote = await auralis.quoteSwap(pool, tokenIn, amountIn);
const amountOutMinimum = minimumAmount(quote.amountOut, 50);
```

`50` basis points equivalen a `0,50 %`. La tolerancia debe considerar profundidad, volatilidad,
latencia del proveedor RPC y valor económico de la operación.

Ejecución Solidity:

```solidity
uint256 amountOut = router.swapExactInputSingle(
    SwapRequest({
        pool: pool,
        tokenIn: tokenIn,
        amountIn: amountIn,
        minimumAmountOut: amountOutMinimum,
        recipient: recipient,
        deadline: block.timestamp + 300
    })
);
```

## Rutas

Cada paso contiene `pool` y `tokenOut`. El router verifica:

- que la ruta no esté vacía;
- que cada pool sea canónico;
- que el token de salida pertenezca al pool;
- que la salida de un paso sea la entrada del siguiente;
- que el último paso respete el mínimo global.

```solidity
RouteStep[] memory route = new RouteStep[](2);
route[0] = RouteStep({pool: poolAB, tokenOut: tokenB});
route[1] = RouteStep({pool: poolBC, tokenOut: tokenC});
```

No utilices la salida cotizada de cada salto como mínimo aislado: el parámetro público protege
el resultado final y permite que pasos intermedios se ajusten al estado ejecutado.

## Aportar liquidez

El router recibe máximos deseados, mínimos aceptables y mínimo de shares:

```solidity
AuralisRouter.AddLiquidityParams memory params = AuralisRouter.AddLiquidityParams({
    pool: pool,
    amount0Desired: amount0,
    amount1Desired: amount1,
    amount0Minimum: minimum0,
    amount1Minimum: minimum1,
    liquidityMinimum: minimumShares,
    recipient: recipient,
    deadline: block.timestamp + 300
});
```

Los tokens deben aprobarse al router. El router aprueba temporalmente al pool, ejecuta el mint,
restablece las allowances a cero y devuelve remanentes.

## Retirar liquidez

`quoteBurn` devuelve principal, fees realizadas y si la solicitud cierra la posición. La
ejecución puede usar allowance ERC-20 o `removeLiquidityWithPermit` con EIP-2612.

```ts
const quote = await auralis.quoteBurn(pool, owner, liquidity);
const minimum0 = minimumAmount(quote.amount0, 30);
const minimum1 = minimumAmount(quote.amount1, 30);
```

Nunca uses mínimos igual a cero en una interfaz destinada a usuarios finales.

## Health monitor

```ts
const health = await auralis.health(pool);
if (!health.healthy) {
  throw new Error(`Pool health flags: ${health.flags}`);
}
```

Los flags son acumulables. Una automatización debe decodificar todos los bits, no detenerse en
el primero. El significado y las acciones se definen en
[risk-and-monitoring.md](./risk-and-monitoring.md).

## Adaptador RPC

`AuralisClient` requiere únicamente:

```ts
interface PublicClient {
  readContract<T>(request: ContractReadRequest): Promise<T>;
}
```

Un adaptador para viem puede delegar directamente en `publicClient.readContract`. Para ethers,
el adaptador puede crear un contrato por ABI y ejecutar la función indicada. Mantén el chain ID
y el bloque de lectura dentro del contexto de tu proveedor.

## Decimales

No mezcles valores humanos con unidades mínimas:

```text
raw = human * 10^tokenDecimals
human = raw / 10^tokenDecimals
```

Las cotizaciones no normalizan automáticamente activos de 6, 8 o 18 decimales. La UI debe
obtener `decimals()` de cada token, validarlo y formatear sin pérdida de precisión.

## Errores y reintentos

- Reintenta lecturas idempotentes ante errores transitorios del RPC.
- No reenvíes automáticamente una transacción revertida sin recotizar.
- Regenera deadline y mínimos después de cambiar de bloque.
- Conserva el hash de transacción, bloque cotizado y parámetros firmados.
- Clasifica de forma separada errores de usuario, política de riesgo y disponibilidad RPC.
