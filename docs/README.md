# Documentación De Auralis

Este directorio reúne la especificación funcional y operativa del protocolo.

| Documento                                          | Contenido                                               |
| -------------------------------------------------- | ------------------------------------------------------- |
| [architecture.md](./architecture.md)               | Componentes, dependencias y flujos de estado.           |
| [accounting.md](./accounting.md)                   | Reservas, shares, fees, swaps y ejemplos numéricos.     |
| [integration.md](./integration.md)                 | Lecturas, cotizaciones, cliente TypeScript y ejecución. |
| [operations.md](./operations.md)                   | Roles, despliegue, configuración y runbooks.            |
| [risk-and-monitoring.md](./risk-and-monitoring.md) | Políticas de riesgo, flags y alertas.                   |

La interfaz Solidity es la autoridad para tipos y firmas. La documentación explica su uso y las
relaciones económicas, pero los integradores deben anclar siempre sus artefactos a un release.
