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
  common.schema.json           → tipos compartidos (Device, InputEvent, Action, Binding, DeviceID, ...)
  envelope.schema.json         → Request, Response, Event (frame de WebSocket)
  methods/                     → un schema por método (params + result)
    list_devices.schema.json
    set_binding.schema.json
    ...
  events/                      → un schema por evento server→client (data)
    input.schema.json
    ...
examples/                      → frames de ejemplo válidos contra los schemas
go/                            → submódulo Go publicado (CHECKED IN, no gitignored)
  go.mod                       → module github.com/JoniDG/keyforge-protocol/go
  protocol/types.go            → tipos Go generados (consumibles via `go get`)
ts/                            → npm package publicado (CHECKED IN, no gitignored)
  package.json                 → name: @jdg-keyforge/protocol
  tsconfig.json
  src/                         → tipos TS generados (auto, checked in)
  dist/                        → tsc output (.d.ts + .js, gitignored)
Makefile                       → comandos: generate, build-ts, validate, clean
```

## Envelope (wire protocol — DECIDIDO 2026-05-04)

Todo frame WebSocket es uno de **tres shapes** discriminados por `type`. Definidos en `schemas/envelope.schema.json`.

### Request (client → server)
Cliente pide algo, espera respuesta correlacionada por `id`.
```json
{ "type": "request", "id": "<uuid>", "method": "list_devices", "params": {} }
```

### Response (server → client)
Server responde a un request. Discriminada por `ok`.
```json
{ "type": "response", "id": "<uuid>", "ok": true,  "data": { ... } }
{ "type": "response", "id": "<uuid>", "ok": false, "error": { "code": "NOT_FOUND", "message": "..." } }
```

### Event (server → client, sin correlación)
Stream de hardware o notificaciones del daemon.
```json
{ "type": "event", "name": "input", "data": { ... } }
```

### Reglas del envelope

- `id` es **string** (UUID v4 / nanoid generado por el cliente). Permite que plugins re-emitan requests sin colisión.
- `method` y `event.name` en **snake_case**. Sin prefijo `c2s_` / `s2c_` — el `type` ya implica dirección.
- `additionalProperties: false` en envelope, `params`, `data`, `error`.
- **Schemas separados:** `envelope.schema.json` define la forma genérica con `params`/`data` como `object` abierto; los schemas en `methods/` y `events/` definen el contenido específico. Validación en runtime es en dos pasos (envelope → contenido según `method`/`name`).

### Versionado: handshake `hello` / `welcome`

Primer mensaje del cliente al conectar es un request `hello` con `protocol_version`. Server responde `welcome` (response.ok=true) o cierra la conexión con error. Después del handshake, los frames **no llevan versión** — el contrato está fijado para la sesión.

```json
// Cliente envía
{ "type": "request", "id": "1", "method": "hello", "params": { "protocol_version": "1", "client": { "name": "keyforge-desktop", "version": "0.1.0" } } }

// Server responde
{ "type": "response", "id": "1", "ok": true, "data": { "server": { "name": "keyforged", "version": "0.1.0" }, "protocol_version": "1" } }
```

## Convenciones de schemas

- **Un schema por método** en `schemas/methods/<name>.schema.json`. El schema define un objeto con `params` y `result` (cada uno es a su vez un schema de objeto).
- **Un schema por evento** en `schemas/events/<name>.schema.json`. El schema define solo `data`.
- Tipos compartidos en `schemas/common.schema.json`, referenciados con `$ref`. Si un tipo lo usa **un solo método/evento**, puede vivir como `$defs` method-local en su propio schema (ej: `ActionDescriptor`/`ParamSpec` en `list_actions`); promoverlo a `common` recién cuando un segundo schema lo necesite. Ambos generadores (`go-jsonschema` y `json-schema-to-typescript`) resuelven `$defs` locales sin problema.
- `$id` único por schema, con path alineado al filesystem (ej: `https://keyforge.dev/schemas/v1/methods/list_devices.schema.json`). Esta alineación permite que `$ref` relativos a archivo (`../common.schema.json#/$defs/Device`) resuelvan igual contra el `$id` (para `ajv`) y contra el path (para `go-jsonschema`, que no indexa por `$id`).
- Cross-file `$ref`s usan **paths relativos al archivo** (`../common.schema.json#/$defs/...`), no URLs absolutas.
- Toda propiedad `required` declarada explícitamente. **Nunca** `additionalProperties: true`.
- Versionar vía `$id` (path `/v1/`). Bumpear major al romper compatibilidad — y el cliente lo señala en el `hello`.
- **Params de acciones built-in:** `Action.params` queda como `object` abierto (genérico). Los params concretos de cada acción built-in viven como `$defs` en `common.schema.json` con el nombre `<Type>ActionParams` (ej: `DelayActionParams`, `MacroActionParams`, `SendKeysActionParams`, `LaunchAppActionParams`). El daemon valida `Action.params` contra el `$def` que corresponde al `type` — mismo esquema two-step que envelope→método. El schema **no** discrimina por `type`; reglas semánticas (ej: un step de `macro` no puede ser otro `macro`) se aplican en `keyforge-core`, no acá. Acciones que componen otras (`macro`) referencian el `$def` genérico `#/$defs/Action` para sus sub-acciones.

## Comandos

```bash
make generate    # genera tipos Go (go/protocol/) y TS (ts/src/) desde schemas/
make build-ts    # cd ts && npm install && tsc → ts/dist/ (.d.ts + .js)
make validate    # valida los archivos en examples/ contra sus schemas
make clean       # borra ts/dist/
```

**Herramientas requeridas (instalar bajo demanda):**
```bash
go install github.com/atombender/go-jsonschema@latest
npm install -g json-schema-to-typescript ajv-cli
```

## Para Claude — cómo ayudarme acá

- **Cuando cree o modifique un schema:** correr `make generate` y verificar que `make validate` pasa. Recordá commitear el diff resultante en `go/protocol/` **y** `ts/src/` — si no, el drift check de CI falla.
- **Cuando agregue un mensaje nuevo:** crear también un `examples/<nombre>.json` que sirva de smoke test.
- **Cuando agregues/cambies un método o evento:** correr también `make build-ts` para verificar que el barrel auto-generado (`ts/src/index.ts`) sigue compilando con el nuevo top-level `Method*`/`Event*`.
- **Nunca** modificar archivos en `ts/src/` ni en `go/protocol/` a mano — son auto-generados (la única excepción son los hand-maintained `ts/package.json`, `ts/tsconfig.json`, `ts/README.md`, `ts/LICENSE`).
- **Cambios breaking** en un schema: bumpear el `$id` a una versión nueva, no romper la actual sin avisar.
- **Flujo de cierre tras el merge (orden estricto).** Este repo publica a npm, así que el cierre de una unidad de trabajo tiene un paso extra que la regla cross-repo de `KEYFORGE-PLAN.md` no contempla. Cuando el owner confirme que el PR fue mergeado:
  1. Limpieza post-merge de la rama (`git checkout main && git pull --prune` + `git branch -d/-D <rama>`).
  2. Crear y pushear los tags anotados `go/vX.Y.Z` y `ts/vX.Y.Z` sobre el commit de merge.
  3. **Esperar a que el owner publique la nueva versión en npm** (`npm publish` lo corre él — el login es interactivo). El registry no está autenticado en esta sesión; ofrecer un `--dry-run` para verificar el tarball, pero **no** dar por cerrada la unidad hasta que el owner confirme el publish.
  4. **Recién después del publish confirmado**, actualizar `KEYFORGE-PLAN.md` (fila de `keyforge-protocol`, checkboxes de la fase, Work log con fecha, cabecera). Actualizar el plan antes del publish corrompe el estado: deja registrado un `@jdg-keyforge/protocol X.Y.Z` que todavía no existe en el registry y que los repos consumidores no pueden instalar.
  Si una versión no necesita publish a npm (cambio que no toca el package TS), saltear el paso 3 y decirlo explícitamente.

## Reglas duras

- 👤 **Identidad del owner:**
  - LICENSE / copyright / contacto público: **Jonathan Daniel Gomez** / `jonathan.d.gomez98@gmail.com`
  - Commits / GitHub: **JoniDG** / `jonathan.d.gomez98+github@gmail.com`
- 🚨 **Antes de cada commit y push:** verificar `git config user.name` = `JoniDG` y `git config user.email` = `jonathan.d.gomez98+github@gmail.com`.
- ❌ **NO commitees** archivos en `ts/dist/` ni `ts/node_modules/` — están en `.gitignore`.
- ❌ **NO uses** `additionalProperties: true` en schemas — debilita el contrato.
- ✅ Cada cambio de schema requiere ejemplo en `examples/`.

## Referencias

- Contexto general del proyecto: [`../CLAUDE.md`](../CLAUDE.md)
- JSON Schema spec (Draft 2020-12): https://json-schema.org/specification.html
