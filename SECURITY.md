# Politica de Seguridad

Auralis modela contratos con custodia y logica economica sensible. Los cambios deben preservar
la reconciliacion entre balances fisicos, reservas contabilizadas, obligaciones de fees y
participaciones emitidas.

## Alcance de Revision

Quedan dentro del alcance:

- Creacion y registro canonico de pools.
- Emision, transferencia y quema de participaciones.
- Cotizacion y liquidacion de swaps exact-input.
- Acumulacion, checkpoint y cobro de comisiones.
- Reserva de comisiones de protocolo.
- Calculo de fees dinamicas.
- Observaciones de precio y consultas TWAP.
- Bandas de desbalance y reservas minimas.
- Permisos administrativos, pausa y recuperacion operativa.
- Router, lens y scripts de despliegue.

Quedan fuera del alcance operativo:

- Custodia de claves de despliegue.
- Frontends, indexadores y servicios de cotizacion externos.
- Puentes y wrappers de activos.
- Tokens con rebases o comisiones sobre transferencia.
- Oraculos externos distintos del acumulador incluido.
- Despliegues en redes publicas.

## Invariantes Esperadas

Para cada activo de un pool:

```text
reserva bruta = reserva activa + fees de LP pendientes + fees de protocolo
saldo fisico  = reserva bruta
```

Adicionalmente:

- Un swap no debe reducir el producto de las reservas activas por errores de redondeo.
- Cobrar una fee reduce por igual la reserva bruta y la obligacion correspondiente.
- Los checkpoints de fee se actualizan antes de cada cambio de balance de shares.
- Transferir shares conserva los derechos ya checkpointed del remitente.
- Las salidas respetan el supply observado antes de la quema.
- Ninguna operacion deja una reserva activa por debajo del minimo configurado.
- Las comisiones cotizadas permanecen dentro de los limites globales y del pool.
- Un pool canonico solo puede existir una vez por par no ordenado.
- Las llamadas externas que mueven activos estan protegidas contra reentrada.

## Controles de Implementacion

- Solidity `0.8.26` con comprobaciones aritmeticas nativas.
- `FullMath.mulDiv` para productos que requieren precision intermedia de 512 bits.
- Transferencias ERC-20 compatibles con tokens que no retornan valor.
- Rechazo explicito de tokens que entregan un importe distinto al solicitado.
- Guard de reentrada en entradas con movimiento de activos.
- Ownership en dos pasos para componentes administrativos.
- Limites superiores para fees, pendientes de protocolo y configuracion de riesgo.
- Deadlines y slippage en la periferia.
- Factory canonica para impedir sustitucion silenciosa de pools.
- Historial circular acotado para evitar crecimiento de storage no controlado.

## Supuestos de Confianza

El propietario de la factory puede actualizar componentes de politica, pausar pools y definir
el receptor de comisiones de protocolo. Estas capacidades deben quedar bajo un multisig o un
timelock en cualquier despliegue persistente. El guardian de emergencia solo debe poder reducir
la superficie operativa y no debe recibir facultades para transferir reservas de LP.

El modelo asume activos ERC-20 con balances estables durante una transaccion. Los integradores
deben verificar decimales, liquidez inicial y parametros de riesgo antes de publicar un pool.

## Validacion Requerida

Antes de aceptar un cambio:

```bash
forge fmt --check
forge build --deny warnings
FOUNDRY_PROFILE=ci forge test --deny warnings
```

Los cambios en contabilidad, shares o fees deben incluir pruebas unitarias y propiedades fuzz.
Los cambios en permisos deben cubrir tanto el camino autorizado como rechazos desde cuentas no
privilegiadas. Los cambios en matematica deben probar limites, redondeo y valores cercanos al
maximo del tipo utilizado.

## Reporte Responsable

Los hallazgos deben comunicarse por el canal privado acordado con el mantenedor. Un reporte util
incluye:

- Resumen y condicion necesaria.
- Contratos y funciones afectados.
- Secuencia minima de reproduccion.
- Impacto economico y activos en riesgo.
- Trazas o tests autocontenidos.
- Mitigacion sugerida y propiedades de regresion.

No se deben publicar pruebas de concepto, transacciones completas ni detalles explotables antes
de coordinar la correccion con el mantenedor.

## Gestion de Dependencias

El protocolo no depende de paquetes Solidity externos en tiempo de compilacion. GitHub Actions
y el toolchain de Foundry se revisan mediante Dependabot. Toda actualizacion del compilador o de
la EVM objetivo debe ejecutar nuevamente la suite completa.

## Restricciones Operativas

- No usar claves reales en tests, scripts o variables versionadas.
- No desplegar con receptores de fees o propietarios temporales.
- No crear pools para tokens no revisados.
- No omitir limites de slippage en automatizaciones.
- No reutilizar observaciones locales como fuente de valoracion externa sin analizar su ventana.
- No conectar el laboratorio a capital real.
