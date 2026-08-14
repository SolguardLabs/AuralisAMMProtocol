# Política De Seguridad

Auralis procesa activos, participaciones y obligaciones contables dentro de contratos con
custodia. La seguridad del protocolo depende tanto de la corrección aritmética como de la
coherencia entre pool, factory, router, oracle, controladores y sistemas operativos externos.

## Versiones mantenidas

| Serie     | Estado      |
| --------- | ----------- |
| `1.0.x`   | Mantenida   |
| `< 1.0.0` | Sin soporte |

Las correcciones se publican mediante releases firmados por tag semántico. Los integradores
deben anclar despliegues y revisiones al commit asociado al release, no a una rama móvil.

## Reporte privado

Utiliza un
[GitHub Security Advisory privado](https://github.com/SolguardLabs/AuralisAMMProtocol/security/advisories/new)
para comunicar un hallazgo. No abras un issue público con trazas, calldata, transacciones o
secuencias reproducibles.

El reporte debe incluir:

- resumen ejecutivo y condición necesaria;
- commit, red, contratos y funciones afectados;
- precondiciones y capacidades requeridas;
- secuencia mínima reproducible;
- impacto económico y activos en riesgo;
- test autocontenido o trazas relevantes;
- mitigación propuesta y propiedades de regresión.

## Proceso de respuesta

1. Confirmación de recepción y clasificación inicial.
2. Reproducción sobre el commit indicado.
3. Evaluación de alcance, impacto y dependencias.
4. Preparación de corrección y tests de regresión.
5. Validación independiente del cambio.
6. Publicación coordinada de release y notas técnicas.

Los plazos dependen del alcance y de la necesidad de coordinación, pero los reportes con riesgo
económico inmediato se priorizan sobre mejoras defensivas o desviaciones sin impacto material.

## Modelo de confianza

### Owner

El owner administra componentes de política y receptores. La cuenta debe estar controlada por
un multisig y, cuando el entorno lo permita, por un timelock con monitorización de operaciones.
La transferencia de ownership requiere aceptación explícita del nuevo owner.

### Guardian

El guardian puede pausar creación y pools, pero no puede restaurar operaciones. Esta asimetría
permite responder a incidentes sin conceder capacidad para reactivar el sistema o mover fondos.

### Fee controller

El controlador determina una tarifa acotada por mínimos y máximos. Una actualización debe
validar límites globales, configuración por pool y disponibilidad de la fuente de volatilidad.

### Oracle

El oracle acumula precios derivados de reservas y mantiene un historial circular. Los
consumidores deben especificar una ventana, comprobar la historia disponible y aplicar un
límite de frescura independiente.

### Activos

El modelo admite ERC-20 con balances estables durante una transacción. Tokens con rebase,
callbacks no estándar o comisión sobre transferencia requieren una integración específica y no
deben incorporarse como si fueran activos estándar.

## Invariantes de seguridad

Para cada activo `i`:

```text
grossReserve_i = activeReserve_i + pendingLPFee_i + protocolFee_i
physicalBalance_i = grossReserve_i
```

Además:

- un swap no reduce el producto de reservas activas por redondeo;
- las salidas nunca superan los límites aportados por el usuario;
- cada cambio de balance de shares checkpointa previamente las fees;
- un pool canónico existe una sola vez por par no ordenado;
- router, lens y monitor rechazan pools ajenos a la factory;
- el guardian solo puede reducir la superficie operativa;
- las reservas activas respetan el suelo y la composición configurados;
- las llamadas que mueven activos están protegidas contra reentrada;
- los nonces EIP-2612 avanzan una sola vez por firma aceptada;
- las cotizaciones no sustituyen los límites de ejecución del usuario.

## Controles automatizados

La validación de release ejecuta:

```bash
forge fmt --check
forge build --sizes --deny warnings
FOUNDRY_PROFILE=ci forge test --deny warnings
npm run format:check
npm run typecheck
npm run test:client
```

La suite incluye tests unitarios, fuzzing matemático, invariantes persistentes, tests del cliente
y señales del monitor operativo. Dependabot revisa GitHub Actions y el toolchain TypeScript.

## Monitoring

`AuralisHealthMonitor` compara balances físicos, reservas, obligaciones, límites de riesgo y
frescura del oracle. Cualquier flag debe interrumpir automatizaciones de liquidez hasta que un
operador clasifique la causa.

El monitor es una capa de detección; no sustituye:

- simulación previa de transacciones;
- límites de slippage y deadline;
- alertas sobre roles administrativos;
- análisis de eventos `Sync`, `Swap`, `Mint`, `Burn` y `FeesClaimed`;
- reconciliación independiente mediante un indexador.

## Gestión de claves y despliegues

- No se versionan claves, mnemónicos, endpoints privados ni archivos `.env`.
- Los scripts leen el firmante desde variables de entorno o un signer administrado.
- Owner, guardian y receptor de fees deben ser direcciones distintas cuando el modelo operativo
  lo requiera.
- Cada despliegue debe registrar chain ID, bytecode, argumentos, direcciones y commit.
- Los cambios de compilador, EVM objetivo o parámetros requieren repetir la suite completa.
- Un release no implica por sí solo autorización para desplegar en una red concreta.

## Alcance

Dentro del alcance:

- contratos bajo `src/`;
- scripts de despliegue y capitalización;
- cliente TypeScript y ABIs mínimos;
- configuración de Foundry y automatización CI;
- interacciones económicas entre pools, router, fee controller, guard y oracle.

Fuera del alcance:

- custodia externa de claves;
- frontends e indexadores no incluidos;
- puentes, wrappers y emisores de los activos;
- disponibilidad o integridad del proveedor RPC;
- protocolos que consuman precios Auralis sin controles propios.
