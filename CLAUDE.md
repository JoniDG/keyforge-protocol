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
  files/                       → formatos de archivo on-disk (ej: plugin_manifest.json), validados contra el `$def` de common con el mismo nombre en PascalCase
go/                            → submódulo Go publicado (CHECKED IN, no gitignored)
  go.mod                       → module github.com/JoniDG/keyforge-protocol/go
  protocol/types.go            → tipos Go generados (consumibles via `go get`)
ts/                            → npm package publicado (CHECKED IN, no gitignored)
  package.json                 → name: @jdg-keyforge/protocol
  tsconfig.json
  src/                         → tipos TS generados (auto, checked in)
  dist/                        → tsc output (.d.ts + .js, gitignored)
Makefile                       → comandos: generate, build-ts, validate (+ validate-files), clean
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

## Manifest y paquete de plugins (DECIDIDO 2026-09-24)

- **Manifest** = `$def PluginManifest` en `common.schema.json` (contrato de archivo on-disk, igual que `ExportedProfile`; no es un mensaje del wire). Ejemplo validado en `examples/files/plugin_manifest.json` vía `make validate-files`.
- **`id` reverse-DNS** (`dev.jonidg.spotify`), para que no choquen ids de distintos autores sin un registry central. `Action.type` de un plugin es `plugin.<id>.<action_id>`; el `action_id` es snake_case sin puntos, así que se parsea cortando en el **último** punto.
- **`entrypoint` por OS** (claves GOOS `darwin`/`linux`/`windows`) → `PluginCommand {path, args?}`. Un `path` con `/` es relativo a la raíz del plugin; un nombre pelado (`node`) se busca en el PATH. El daemon no conoce runtimes. Los OS soportados son las claves presentes.
- `manifest_version` (const 1) versiona el formato del archivo; `protocol_version` (const "1") permite rechazar un plugin incompatible antes de lanzarlo.
- `PluginAction.inputs` opcional (`InputKind[]`) restringe a qué tipo de input se puede bindear la acción (equivalente a `Controllers` de Stream Deck). Los params reusan `ParamSpec`, que se movió a `common`.
- **Paquete `.keyforgeplugin`** (en minúsculas): zip con `manifest.json` en la raíz (sin carpeta que lo envuelva). Se instala extrayéndolo en `<config dir>/plugins/<id>/`.
- **Paths de archivo** (`icon`, `entrypoint` con `/`): relativos a la raíz del plugin, siempre con `/` (también en Windows). El schema rechaza lo sintáctico (`/` inicial, `\`, `:`); lo que **no** puede expresar en RE2 sin lookaheads —segmentos `..`, zip-slip al extraer, unicidad de `actions[].id`/`params[].name`— lo valida `keyforge-core`, y así queda escrito en las descripciones del schema.
- Los `pattern` tienen que compilar en **RE2**: el Go generado ignora el error de `regexp.MatchString`, así que un patrón inválido rechazaría todos los manifests en silencio.
- Fuera de v1: Property Inspector HTML, permisos, estados/íconos por acción, multi-arch dentro de un mismo OS.
- `PluginID` es un `$def` propio (patrón único) que usan `PluginManifest.id` y `PluginLaunchInfo.plugin_id`.

## Runtime de plugins (DECIDIDO 2026-09-24)

- **Lanzamiento:** el daemon spawnea el `entrypoint` y pasa una sola env var `KEYFORGE_PLUGIN_INFO` = JSON `PluginLaunchInfo {plugin_id, ws_url, protocol_version}` (tipado, extensible de forma aditiva). Env var y no args: el token no queda visible en `ps`.
- **Auth/identidad:** `ws_url` lleva un **token por plugin**, distinto del de la GUI. El daemon identifica al plugin por el token; en el `hello`, `client.name` = `PluginID` y el daemon lo cruza contra el token (si no coincide: `FORBIDDEN` + cierre de la conexión).
- **Dispatch:** evento `action_invoked` (`data {context, action: {id, params}, input?: InputEvent}`). `context` = id opaco, requerido, único por binding y por paso de macro y estable mientras exista el binding, incluso entre reinicios del daemon (equivale al `context` de Stream Deck: estado por instancia). `input` es opcional: falta cuando el disparo no vino del hardware (ej: probar la acción desde la GUI); se decidió ahora porque pasarlo de requerido a opcional después es breaking. El evento va **dirigido** solo a la conexión de ese plugin (lo dispara un binding o un paso de macro), `params` siempre presente (`{}` si no hay) y **fire-and-forget**: el envelope no cambia (sigue siendo request solo client→server). Contra aceptado: una macro con un paso de plugin no se entera si ese paso falla.
- **Permisos:** allowlist mínima. Una conexión de plugin solo puede llamar a `hello` y solo recibe sus `action_invoked`; cualquier otro método → error `FORBIDDEN`. Esto no se expresa en el schema; lo aplica `keyforge-core`.
- **Cleanup:** el plugin tiene que terminar cuando se cierra su conexión (así el daemon los baja al apagarse o al desinstalar).
- Métodos de instalación (`install_plugin`/`list_plugins`/`uninstall_plugin`, para la UI de desktop) van en un PR aparte.

## Comandos

```bash
make generate    # genera tipos Go (go/protocol/) y TS (ts/src/) desde schemas/
make build-ts    # cd ts && npm install && tsc → ts/dist/ (.d.ts + .js)
make validate    # valida los archivos en examples/ contra sus schemas (incluye validate-files:
                 # examples/files/<snake>.json contra common#/$defs/<Pascal>)
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
