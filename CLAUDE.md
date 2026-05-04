# CLAUDE.md — keyforge-protocol

## Objetivo
Definir el **contrato** que comparten todos los componentes de KeyForge (daemon, GUI, plugins): mensajes JSON sobre WebSocket descritos como **JSON Schema**.

Este repo es la fuente única de verdad de los tipos. Los demás repos consumen los **tipos generados** (Go y TS) desde acá.

## Scope
- Definir schemas JSON de los mensajes y tipos compartidos.
- Generar tipos Go y TypeScript automáticamente vía `make generate`.
- Proveer ejemplos validables.
- **NO contiene lógica de runtime, validación ni transporte** — solo el contrato.

## Layout
```
schemas/
  common.schema.json           → tipos compartidos (Action, InputEvent, Binding, DeviceID)
  messages/
    c2s_set_binding.schema.json    → client → server
    s2c_input_event.schema.json    → server → client
    ... (ir agregando uno por mensaje)
examples/                      → mensajes de ejemplo válidos contra los schemas
dist/                          → output de generadores (gitignored)
  go/                          → tipos Go generados
  ts/                          → tipos TS generados
Makefile                       → comandos: generate, validate, clean
```

## Convenciones de schemas

- Un schema JSON por mensaje, en `schemas/messages/`.
- Prefijo `c2s_` (client→server) o `s2c_` (server→client) para que sea evidente la dirección.
- Tipos compartidos en `schemas/common.schema.json`, se referencian con `$ref`.
- `$id` único por schema, `title` legible, `description` con propósito.
- Toda propiedad `required` declarada explícitamente. **Nunca** `additionalProperties: true`.
- Versionar el schema vía `$id` (ej: `https://keyforge.dev/schemas/v1/common.json`). Bumpear major al romper compatibilidad.

## Comandos

```bash
make generate    # genera tipos Go (dist/go/) y TS (dist/ts/) desde schemas/
make validate    # valida los archivos en examples/ contra sus schemas
make clean       # borra dist/
```

**Herramientas requeridas (instalar bajo demanda):**
```bash
go install github.com/atombender/go-jsonschema@latest
npm install -g json-schema-to-typescript ajv-cli
```

## Para Claude — cómo ayudarme acá

- **Cuando cree o modifique un schema:** correr `make generate` y verificar que `make validate` pasa.
- **Cuando agregue un mensaje nuevo:** crear también un `examples/<nombre>.json` que sirva de smoke test.
- **Nunca** modificar archivos en `dist/` — son auto-generados.
- **Cambios breaking** en un schema: bumpear el `$id` a una versión nueva, no romper la actual sin avisar.

## Reglas duras

- 👤 **Identidad del owner:**
  - LICENSE / copyright / contacto público: **Jonathan Daniel Gomez** / `jonathan.d.gomez98@gmail.com`
  - Commits / GitHub: **JoniDG** / `jonathan.d.gomez98+github@gmail.com`
- 🚨 **Antes de cada commit y push:** verificar `git config user.name` = `JoniDG` y `git config user.email` = `jonathan.d.gomez98+github@gmail.com`.
- ❌ **NO commitees** archivos en `dist/` — están en `.gitignore`.
- ❌ **NO uses** `additionalProperties: true` en schemas — debilita el contrato.
- ✅ Cada cambio de schema requiere ejemplo en `examples/`.

## Referencias

- Contexto general del proyecto: [`../CLAUDE.md`](../CLAUDE.md)
- JSON Schema spec (Draft 2020-12): https://json-schema.org/specification.html
