# Modelo Contable

## Unidades

Todos los importes de activos se expresan en sus unidades mínimas ERC-20. Auralis no normaliza
automáticamente decimales entre activos. Las shares usan 18 decimales; precios e índices usan
formatos fijos Q112 o Q128 según el dominio.

| Dominio             | Unidad                    |
| ------------------- | ------------------------- |
| Reservas e importes | Unidad mínima del token   |
| Fee de swap         | Partes por millón (`1e6`) |
| Share del protocolo | Partes por millón (`1e6`) |
| Índice de fee       | Q128                      |
| Precio acumulado    | Q112 por segundo          |
| Desbalance          | Partes por millón (`1e6`) |

## Dominios de reserva

Para cada activo `i`:

```text
B_i = reserva bruta almacenada
F_i = fee pendiente frente a LPs
P_i = fee propiedad del protocolo
R_i = reserva activa

R_i = B_i - F_i - P_i
```

`B_i` debe coincidir con `balanceOf(pool)`. Las fees no forman parte de la liquidez disponible
para swaps, aunque permanezcan físicamente en el contrato hasta su realización.

Ejemplo:

```text
B_0 = 1.025.000
F_0 =    20.000
P_0 =     5.000
R_0 = 1.000.000
```

El invariante y el límite de composición utilizan `R_0`, no el saldo bruto.

## Liquidez inicial

La primera aportación calcula:

```text
geometricMean = floor(sqrt(amount0 * amount1))
liquidity = geometricMean - MINIMUM_LIQUIDITY
```

`MINIMUM_LIQUIDITY` se emite de forma permanente a una dirección sin control para impedir que el
supply vuelva a cero mientras el pool exista.

## Aportaciones posteriores

El pool acepta la mayor combinación compatible con el ratio activo:

```text
amount1Optimal = floor(amount0Desired * active1 / active0)
```

Si `amount1Optimal` supera el máximo aportado, el cálculo se invierte usando `amount1Desired`.
Las shares emitidas son:

```text
shares = min(
  floor(amount0 * totalSupply / active0),
  floor(amount1 * totalSupply / active1)
)
```

El router devuelve al remitente cualquier remanente no utilizado.

## Settlement de shares

`LiquiditySettlement` recibe un contexto inmutable de la operación y devuelve:

```text
amount_i = principal_i + realizedFee_i
```

La cotización conserva por separado principal, fee realizada y si la operación cierra la
posición. Esta descomposición permite que router, lens e indexadores compartan la misma semántica
sin reconstruirla a partir de eventos.

Para una base económica `E_i` y una quema `L`:

```text
principal_i = floor(L * E_i / totalSupply)
```

Los límites `amount0Minimum` y `amount1Minimum` se validan después de construir la cotización y
antes de quemar shares o transferir activos.

## Acumulación de fees

Cada swap aumenta el índice global del activo de entrada:

```text
feeGrowthDeltaX128 = floor(lpFee * 2^128 / feeBearingSupply)
feeGrowthGlobalX128 += feeGrowthDeltaX128
```

Para una cuenta con `shares`:

```text
growthDelta = globalGrowth - accountCheckpoint
newAccrued = floor(shares * growthDelta / 2^128)
```

El checkpoint se ejecuta antes de mint, burn o transferencias de shares. El supply bloqueado en
la dirección de liquidez mínima no participa en la distribución.

## Swap exact-input

La entrada bruta se divide:

```text
totalFee = floor(amountIn * feePpm / 1_000_000)
protocolFee = floor(totalFee * protocolSharePpm / 1_000_000)
lpFee = totalFee - protocolFee
netAmountIn = amountIn - totalFee
```

La salida de la curva es:

```text
amountOut = floor(netAmountIn * reserveOut / (reserveIn + netAmountIn))
```

Debido al redondeo hacia abajo:

```text
(reserveIn + netAmountIn) * (reserveOut - amountOut) >= reserveIn * reserveOut
```

Antes de ejecutar, el pool proyecta las dos reservas resultantes y consulta
`ImbalanceGuard.checkVirtualReserves`.

## Reconciliación

Un indexador debe reconstruir, por bloque:

1. `getReserves()` para reservas brutas.
2. `pendingLPFees()` y `protocolFees()` para obligaciones.
3. `activeReserves()` para la curva.
4. balances físicos de token para confirmar custodia.
5. `totalSupply()` y balances de shares para posiciones.

La igualdad básica es:

```text
physical_i = gross_i = active_i + pendingLPFee_i + protocolFee_i
```

`AuralisHealthMonitor` automatiza esta comprobación para consumo on-chain. La reconciliación de
un indexador externo sigue siendo necesaria para alertas históricas y atribución de eventos.
