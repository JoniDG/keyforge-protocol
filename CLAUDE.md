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
- **Params de acciones built-in:** `Action.params` queda como `object` abierto (genérico). Los params concretos de cada acción built-in viven como `$defs` en `common.schema.json` con el nombre `<Type>ActionParams` (ej: `DelayActionParams`, `MacroActionParams`, `SendKeysActionParams`, `LaunchAppActionParams`). El daemon valida `Action.params` contra el `$def` que corresponde al `type` — mismo esquema two-step que envelope→método. El schema **no** discrimina por `type`; reglas semánticas (ej: un paso de `macro` o de `toggle` no puede ser `macro` ni `toggle`) se aplican en `keyforge-core`, no acá. Acciones que componen otras (`macro`, `toggle`) referencian el `$def` genérico `#/$defs/Action` para sus sub-acciones.

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

## Instalación de plugins (DECIDIDO 2026-09-24)

Cuatro métodos. Igual que en `import_profile`, el daemon es el que toca el filesystem y la GUI solo le pasa el path que resolvió con un diálogo nativo.

- `inspect_plugin {path} → {manifest, installed_version?}`: valida el paquete igual que `install_plugin` pero sin instalar, para que la GUI muestre una confirmación. `installed_version` permite mostrar "actualizar de X a Y". La validación del zip queda en un solo lugar: el daemon.
- `install_plugin {path} → {plugin, previous_version?}`: si el id ya existe, **reemplaza** (upgrade): baja el proceso viejo, cambia la carpeta de forma atómica y lanza la versión nueva. Nunca toca bindings, así que siguen andando tras un upgrade. Responde apenas spawnea (no espera el `hello`), así que devuelve `status: starting` y la GUI refresca con `list_plugins`.
- `inspect_plugin` e `install_plugin` **rechazan** un paquete sin entrypoint para el SO del host: nunca queda instalado un plugin que no puede correr. `status: error` queda solo para fallas al arrancar o crashes.
- `list_plugins {} → {plugins: InstalledPlugin[]}`. `$def InstalledPlugin {manifest, status: starting|running|stopped|error, error?}` en `common` (lo usan install y list). `starting` se agregó ahora porque sumar un valor al enum más adelante rompe clientes viejos (el `UnmarshalJSON` de Go rechaza valores desconocidos). `error` solo aparece con `status: error`; lo garantiza el daemon, no el schema.
- `uninstall_plugin {id} → {}`: baja el proceso y borra la carpeta. Los bindings quedan **huérfanos**: dispararlos no hace nada, y al reinstalar vuelven a andar. Nunca se borra configuración del usuario.
- Los códigos de error de estos métodos los define `keyforge-core` como sentinels (mismo criterio que import/export); el schema no los enumera.
- Pendiente (aditivo, sin fecha): un evento de cambio de estado de plugins para que la GUI se entere de crashes sin re-pedir `list_plugins`.

## Colores de inputs / RGB (DECIDIDO 2026-09-30)

API hardware-agnóstica: "poné este color en el input X". Lo específico de cada dispositivo (en el keypad de referencia, pasar al efecto `05` user light antes de pintar por tecla) lo resuelve el daemon.

- **`$def Color`** = string `#RRGGBB` (se acepta en cualquier case; el daemon lo guarda y devuelve en minúsculas para que la GUI compare strings; patrón RE2). Hex y no `{r,g,b}`: es lo que devuelve un color picker y se lee bien en JSON. `#000000` = apagado.
- **Capacidad:** `Input.rgb?: boolean` (ausente = false). Boolean y no enum (`rgb`/`mono`): agregar valores a un enum después rompe clientes Go viejos. LEDs monocromo, si aparecen, van como campo aditivo aparte.
- **Los colores son por perfil** (decisión del owner): `Profile.colors?` / `ExportedProfile.colors?` = `InputColor[] {device_id, input_id, color}` (array como `bindings`, no mapa). Al activarse un perfil el daemon repinta todos los inputs RGB; un input RGB sin entrada queda apagado. Unicidad por `(device_id, input_id)` la garantiza `keyforge-core`, no el schema. Opcionales para no romper consumidores contra un daemon viejo; `ExportedProfile.version` sigue en `1` (bumpear no ayuda: un lector viejo rechaza el campo nuevo si valida contra el schema, o lo descarta en silencio si solo hace `json.Unmarshal`; en ningún caso lo aprovecha).
- **`set_input_color {device_id, input_id, color} → {}`**: escribe en el perfil **activo** (igual que `set_binding`, sin `profile_id`) y pinta en el momento. Rechaza inputs desconocidos o sin LED; los códigos de error los define `keyforge-core` como sentinels.
- **Estado leíble:** `Input.color?` en `list_devices` = color que el perfil activo pinta en ese input (ausente = apagado). El daemon persiste los colores dentro del perfil y los re-aplica al reconectar el dispositivo.
- Fuera de v1: efectos/animaciones, método batch, que un plugin pinte LEDs (la allowlist de plugins sigue siendo solo `hello`).

## Acción built-in `set_color` (DECIDIDO 2026-10-05)

Cambiar colores como side effect de un binding (indicador "grabando", "muteado", etc.).

- **`$def SetColorActionParams {color, input_id?, device_id?, persist?}`** en `common`, como el resto de las `<Type>ActionParams`.
- **Target:** sin `input_id` pinta el input que disparó la acción; sin `device_id`, el mismo dispositivo. `device_id` solo vale junto con `input_id` (`dependentRequired` en el schema; `go-jsonschema` lo ignora, así que core lo valida al guardar el binding). Sin disparo de hardware (prueba desde la GUI) y sin `input_id`, la acción falla. Un input desconocido o sin LED falla **al ejecutarse**, no al guardar el binding (el dispositivo puede estar desconectado). Todo esto lo valida `keyforge-core`.
- **`persist` decide el alcance, por binding** (decisión del owner: tienen que existir las dos cosas). `false` (default) = efímero: solo pinta; `Profile.colors` no cambia, `Input.color` sigue mostrando el color del perfil y ese color vuelve al activarse un perfil o reconectar el dispositivo. `true` = además escribe en el perfil activo, igual que `set_input_color`.
- "Cambiar el set de colores" desde una tecla = un `macro` con varios `set_color`. Sets con nombre y una acción "aplicá el set X" quedan como agregado futuro; el toggle (tocar de nuevo y volver al color anterior) es la acción `toggle`, no parte de `set_color` (ver más abajo).
- **`ParamSpec.type`** suma `boolean` y `color` (un color picker en la GUI), así la GUI renderiza el formulario de `set_color` de forma genérica y los plugins también pueden pedir colores. Un boolean opcional ausente = `false`; `placeholder` solo aplicaba a `string` (desde 0.15.1 también a `input`, ver más abajo). Agregar valores a un enum rompe a un consumidor Go viejo: su `UnmarshalJSON` rechaza el valor y falla la respuesta **entera** de `list_actions`, `inspect_plugin`/`install_plugin`/`list_plugins` y la carga de cualquier `manifest.json` que use `boolean`/`color` (`ParamSpec` vive en `PluginManifest`); un desktop viejo parsea bien pero su formulario recibe un `type` que no conoce. Se aceptó porque core y desktop salen juntos y todavía no hay plugins de terceros.

## Acción built-in `toggle` (DECIDIDO 2026-10-07)

Alternar entre dos comportamientos con la misma tecla (grabar + rojo / parar + verde). Modelo copiado del **Multi Action Switch** de Stream Deck.

- **`$def ToggleActionParams {on, off}`** en `common`: cada lado es **una lista de acciones** (`Action[]`, `minItems 1`), no una sola acción. Así el usuario no tiene que envolver en `macro` para hacer dos cosas, y la GUI reusa el editor de pasos de macro para cada lado. Se descartó `cycle {steps}` (N estados): si hace falta, se suma como acción aparte de forma aditiva.
- **Sin anidamiento** (como Stream Deck): un paso de `on`/`off` no puede ser `macro` ni `toggle`, y un `toggle` no puede ser paso de una `macro`. Profundidad máxima: un nivel. El schema permite cualquier `Action` (igual que `macro`); lo rechaza `keyforge-core` al guardar el binding.
- **Ejecución:** cada lista corre en orden como una macro y corta en el primer fallo.
- **Estado en memoria, por binding** (decisión del owner): arranca en `on` al iniciar el daemon y al guardar el binding (`set_binding`); no se resetea al cambiar de perfil. No se persiste porque el daemon no sabe el estado real de afuera (tras un reinicio, OBS ya no está grabando).
- **Solo avanza si la lista salió entera bien** (decisión del owner): un `on` fallido se reintenta en el próximo disparo. Un paso de plugin cuenta como éxito apenas se manda `action_invoked` (es fire-and-forget).
- **`context` de plugins:** único por binding y por paso de cada lista del toggle (descripción de `action_invoked` actualizada; solo comentarios en los tipos).
- **`list_actions`:** igual que `macro`, el descriptor no declara `ParamSpec` (no hay tipo para "lista de acciones"); el cliente renderiza un editor dedicado.
- Fuera de v1: exponer el estado actual a la GUI, un método para resetearlo, o íconos/colores atados al estado (el color se pinta con un paso `set_color` en cada lista). Ojo: un `set_color` efímero vuelve al color del perfil al cambiar de perfil, mientras el estado del toggle se mantiene.

## Param de tipo `input` (DECIDIDO 2026-10-05)

Para que un param que apunta a un input (`set_color.input_id`, o el input que pida un plugin) se elija de una lista y no como texto libre con ids internos (`key_0x68`). Se resolvió en el contrato y no como caso especial del desktop, para que sirva igual a built-ins y plugins.

- **`ParamSpec.type`** suma `input`. En `Action.params` se escribe un string con el `Input.id` de un input del **mismo device del binding**. El selector no apunta a otro device por ahora (decisión del owner): `SetColorActionParams.device_id` sigue existiendo, pero el registry no lo anuncia. Abrirlo después es aditivo.
- **Render:** un selector con los inputs de ese device, nombrados y ordenados como en el editor visual (`Input.label`, o la numeración por kind en orden de lectura de la vista rotada). Si el param es opcional y queda ausente, significa "sin elegir" y cada acción define qué hace (en `set_color`, pinta el input que disparó). `placeholder` (0.15.1, antes solo `string`) es la etiqueta de esa opción "sin elegir" y describe qué hace la acción en ese caso (`set_color`: "This key (the one that fired)"); en un param requerido no hay opción vacía y el cliente lo ignora. No aplica a `boolean` ni a `color`. Cambio solo de descripción: los tipos generados cambian únicamente en comentarios.
- **Rotación:** se guarda siempre el `Input.id` (la identidad física), nunca la posición ni el label numerado. Rotar el device no cambia a qué tecla apunta el param, pero sí cambia el label que muestra el selector. El cliente traduce en los dos sentidos con la rotación vigente.
- **`$def InputFilter {kinds?, rgb?}`** en `common`, usado como `ParamSpec.input_filter?` (nombre elegido por el owner; `inputs` se descartó porque se confunde con `PluginAction.inputs`). `kinds`: `minItems 1`, `uniqueItems`; si falta, acepta cualquier kind. `rgb: true` deja solo inputs con LED; `false` o ausente no filtra. `set_color` anuncia `input_id` como `{type: "input", input_filter: {rgb: true}}`; si un binding guardado trae `device_id`, el `input_id` es de ese otro device y el cliente lo muestra tal cual. Un plugin puede pedir un input, pero pintar LEDs sigue fuera de su allowlist (solo `hello`).
- **`input_filter` solo vale con `type: "input"`.** En el schema se expresa con `if/then` (`dependentRequired` no sirve porque la condición depende del valor de `type`). Los dos generadores ignoran el `if/then`, y el Go tampoco chequea `uniqueItems`: lo valida `keyforge-core`. Que el id exista en el device se valida al ejecutar, no al guardar (el device puede estar desconectado).
- **Compatibilidad:** igual que `boolean`/`color` en `0.14.0`, sumar `input` al enum rompe a un consumidor Go viejo (falla entera la respuesta de `list_actions` y los métodos/archivos que traen `PluginManifest`). Se aceptó porque core y desktop salen juntos.

## Perfiles y auto-switch (DECIDIDO 2026-10-03)

Ningún método deja reglas de auto-switch apuntando a un perfil inexistente. No se expresa en el schema (necesita estado); lo aplica `keyforge-core` y queda escrito en las descripciones. Un archivo de config editado a mano puede igual tener reglas huérfanas.

- `delete_profile` borra también las reglas de auto-switch cuyo `profile_id` es el perfil borrado.
- `set_auto_switch` rechaza el request entero con `PROFILE_NOT_FOUND` si alguna regla apunta a un perfil que no existe; no persiste nada. Excepción a "el schema no nombra códigos de error": `PROFILE_NOT_FOUND` ya lo emite `keyforge-core` y lo mapea `keyforge-desktop`, así que nombrarlo solo documenta un código que ya es parte del contrato.

## Layout de dispositivos y rotación (DECIDIDO 2026-10-04)

La distribución física viaja en el contrato para que la GUI pueda dibujar cualquier dispositivo, no solo el keypad de referencia. El catálogo de `keyforge-hid` completa el layout y `keyforge-core` persiste la rotación.

- **`$def InputLayout {x, y, w?, h?}`** en unidades de tecla (1 = una tecla estándar, se aceptan fracciones; `w`/`h` ausentes = 1). Es el modelo de QMK/VIA (`info.json`). `Input.layout?` es opcional: si todos los inputs de un dispositivo traen layout, el cliente lo dibuja; si falta en alguno, cae a una vista sin posiciones (lista). La forma no se modela: sale de `kind` (key = rectángulo, encoder = círculo).
- **Orientación canónica:** el layout es un sistema de coordenadas que define el catálogo (origen arriba a la izquierda, `y` crece hacia abajo), no cómo el usuario tiene apoyado el dispositivo.
- **`Input.label` = nombre fijo** (`Enter`, `Play`) que se muestra igual en cualquier orientación. Si falta, el cliente numera por posición: por kind, en orden de lectura de la vista ya rotada, ordenando por la esquina superior izquierda de cada input (primero `y`, después `x`), así "Key 1" es siempre la de arriba a la izquierda tal como está apoyado. Sin layout completo, numera por kind en el orden en que `list_devices` devuelve los inputs. Los catálogos **no** mandan labels posicionales ("Key 1"): con la rotación quedarían mal. Cambio solo de descripción.
- **`$def DeviceRotation`** = enum entero `0|90|180|270` (grados en sentido horario sobre la orientación canónica); `Device.rotation?` (ausente = 0). Solo presentación: bindings y colores siguen atados al `input_id`. Es **por dispositivo, no por perfil**: no cambia al cambiar de perfil.
- **`set_device_rotation {device_id, rotation} → {}`** (ack vacío, como `set_input_color`): persiste por `device_id` y `list_devices` la expone. Rechaza `device_id` desconocidos; los códigos de error los define `keyforge-core`.
- **Gotcha del generador Go:** si `common.schema.json` se procesa primero, `go-jsonschema` duplica un `$def` enum **entero** referenciado desde otro archivo (`DeviceRotation_1`). Por eso el `Makefile` le pasa métodos y eventos antes que `common`. Además, un `$ref` con `description` al lado hace que `json2ts` emita un alias duplicado (`Color1`): para `$def`s compartidos, la descripción va en el `$def`.

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
