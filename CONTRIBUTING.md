# Contribución

## Flujo

1. Crea una rama desde `main`.
2. Mantén el cambio limitado a una responsabilidad.
3. Añade tests para caminos válidos y rechazos.
4. Ejecuta `npm ci` y `bash scripts/ci.sh`.
5. Explica impacto económico, ABI y almacenamiento en el pull request.

## Convenciones

- Código, nombres y comentarios de código en inglés.
- Documentación de producto en español.
- Solidity formateado con `forge fmt`.
- TypeScript, Markdown, JSON y YAML formateados con Prettier.
- Errores personalizados en lugar de strings de revert.
- Conversiones estrechas precedidas por una comprobación explícita.
- Ninguna llamada externa antes de consolidar el estado correspondiente.
- Funciones públicas documentadas con NatSpec.

## Tests

Selecciona la capa adecuada:

- `tests/unit`: comportamiento funcional y permisos.
- `tests/fuzz`: propiedades aritméticas sobre rangos amplios.
- `tests/invariant`: propiedades persistentes tras secuencias de operaciones.
- `client/*.test.ts`: adaptación, tipos y construcción de solicitudes.

Los tests deben ser deterministas y no depender de RPC, timestamps reales ni servicios externos.

## Cambios sensibles

Un cambio en reservas, fees, shares, settlement, oracle o roles debe incluir:

- descripción del estado anterior y posterior;
- fórmula o invariante afectada;
- análisis de redondeo;
- compatibilidad de storage y ABI;
- tests negativos y de límites;
- plan de migración si ya existe una versión desplegada.

Los asuntos de seguridad se comunican mediante el proceso privado descrito en
[SECURITY.md](./SECURITY.md).
