# keyforge-protocol

> Wire protocol contracts for the [KeyForge](https://github.com/JoniDG/keyforge) ecosystem.

This repository defines the **JSON Schema** contracts shared between the KeyForge daemon, GUI and plugins. All messages travel as JSON over a local WebSocket. Strongly-typed Go and TypeScript bindings are generated automatically from the schemas.

## Status

🚧 **Pre-alpha.** APIs are not stable yet.

## Wire protocol

Every WebSocket frame is one of three shapes, discriminated by the `type` field:

| Shape | Direction | Purpose |
|---|---|---|
| `request` | client → server | RPC call. Includes a client-generated `id` for correlation. |
| `response` | server → client | Reply correlated by `id`. `ok: true` carries `data`; `ok: false` carries an `error`. |
| `event` | server → client | Uncorrelated stream (hardware events, daemon notifications). |

The envelope is generic — `params` and `data` are arbitrary objects at the envelope level. **Method-** and **event-specific schemas refine those payloads** in a second validation pass.

The first request after a connection is established is `hello`, where the client declares the protocol version it speaks. The server either accepts it (`response.ok=true`) or closes the connection. Subsequent frames carry no version.

See [`schemas/envelope.schema.json`](schemas/envelope.schema.json) for the formal definition and [`examples/frames/`](examples/frames/) for sample frames of every shape.

## Layout

```
schemas/
  common.schema.json     # shared types: Device, DeviceID, Input, InputEvent, Action, Binding, ...
  envelope.schema.json   # request / response / event frames
  methods/               # one schema per RPC method (params + result)
    hello.schema.json
    list_actions.schema.json
    list_bindings.schema.json
    list_devices.schema.json
    set_binding.schema.json
  events/                # one schema per server-to-client event (data)
    input.schema.json
examples/
  frames/                # complete envelope frames (validated against envelope.schema.json)
  methods/               # logical { params, result } payloads (validated against the method schema)
  events/                # logical { data } payloads (validated against the event schema)
  files/                 # on-disk file formats, e.g. plugin_manifest.json (validated against the matching common $def)
go/                      # Go submodule (checked in; consumed via `go get`)
  go.mod                 # module github.com/JoniDG/keyforge-protocol/go
  protocol/              # generated Go types
ts/                      # TS npm package (checked in; consumed via `npm install`)
  package.json           # name: @jdg-keyforge/protocol
  tsconfig.json
  src/                   # generated TS source (auto-generated, checked in)
  dist/                  # tsc output: .d.ts + .js (git-ignored)
```

## Quickstart

```bash
# Install generators (one-time)
go install github.com/atombender/go-jsonschema@latest
npm install -g json-schema-to-typescript ajv-cli ajv-formats

# Validate the example messages against their schemas
make validate

# Generate Go and TS types from schemas
make generate
```

Generated types land in `go/protocol/types.go` and `ts/src/*.ts` — both checked in so downstream consumers can pull them without running the generators locally.

> **Note:** `make` automatically prepends `$(go env GOPATH)/bin` to `PATH`, so `go-jsonschema` is found even if you have not added `~/go/bin` to your shell `PATH`.

## Schema conventions

- `$id` paths mirror the filesystem (e.g. `https://keyforge.dev/schemas/v1/methods/hello.schema.json`).
- Cross-file `$ref`s use **file-relative paths** (`../common.schema.json#/$defs/Device`), so both `ajv` and `go-jsonschema` resolve them consistently.
- Method names and event names are **`snake_case`** (no `c2s_` / `s2c_` prefix — the envelope `type` already implies direction).
- `additionalProperties: false` on every object. `required` declared explicitly.

## Plugin manifest and package format

A plugin declares itself in a `manifest.json`, defined by the `PluginManifest` type in [`schemas/common.schema.json`](schemas/common.schema.json). See [`examples/files/plugin_manifest.json`](examples/files/plugin_manifest.json) for a complete example.

- **`id`** is reverse-DNS (`dev.jonidg.spotify`), so ids from different authors don't collide without a central registry.
- **Actions** are bound as `plugin.<id>.<action id>` (e.g. `plugin.dev.jonidg.spotify.play_pause`). Action ids are `snake_case` and never contain dots, so the action id is everything after the last dot.
- **`entrypoint`** maps each supported OS (`darwin`, `linux`, `windows`) to an executable plus optional `args`. A `path` containing `/` is relative to the plugin root; a bare name (e.g. `node`) is looked up on the `PATH`. The daemon knows nothing about runtimes; it just spawns the command.
- **`protocol_version`** lets the daemon reject an incompatible plugin before spawning it.
- An action's optional **`inputs`** restricts which input kinds (`key`, `encoder`) it can be bound to.
- **Params** are described with `ParamSpec`, whose `type` is `string`, `boolean`, `color` or `input`. An `input` param stores the `Input.id` of an input on the same device as the binding, and clients render it as a picker of that device's inputs, named as in the visual editor. The optional `input_filter { kinds?, rgb? }` narrows the list (e.g. `rgb: true` for inputs with an LED). In an optional `input` param, `placeholder` labels the picker's "nothing picked" option and says what the action does then (e.g. `set_color` paints the key that fired). The stored value is always the physical input id, so rotating the device doesn't change which input a param targets.

Plugins are distributed as a **`.keyforgeplugin`** file: a zip archive with `manifest.json` at its root (no wrapping folder) plus every file the manifest references. The daemon installs it by extracting the archive into `<config dir>/plugins/<id>/`, taking the id from the manifest. All file paths in the manifest (`icon`, and entrypoint paths containing `/`) are relative to the plugin root, use `/` as separator (also on Windows), and must stay inside the plugin root: the daemon rejects `..` segments and any path or archive entry that escapes it.

## Plugin runtime

How the daemon runs an installed plugin and talks to it:

1. **Launch.** The daemon spawns the manifest's `entrypoint` for the current OS and sets the `KEYFORGE_PLUGIN_INFO` environment variable to a JSON `PluginLaunchInfo` (`plugin_id`, `ws_url`, `protocol_version`). An env var is used instead of CLI args so the auth token doesn't show up in the process list. See [`examples/files/plugin_launch_info.json`](examples/files/plugin_launch_info.json).
2. **Connect.** The plugin opens `ws_url`, which carries a **per-plugin token** distinct from the GUI's, and sends the regular `hello` with `client.name` set to its plugin id. The daemon identifies the plugin by its token; a `hello` whose name doesn't match is answered with `FORBIDDEN` and the connection is closed.
3. **Receive actions.** When a binding or macro step for `plugin.<plugin_id>.<action_id>` fires, the daemon sends the `action_invoked` event to that plugin's connection only, with an opaque `context` (stable per binding instance, so a plugin can keep per-instance state), the action id, its params and, when the trigger came from hardware, the `InputEvent` that fired it. Delivery is fire-and-forget: the daemon doesn't wait for the plugin.
4. **Permissions.** A plugin connection may only call `hello` and only receives its own `action_invoked` events (no `input` or GUI-facing events). Any other method is answered with error code `FORBIDDEN`.
5. **Exit.** A plugin must exit when its WebSocket connection closes. That's how the daemon stops plugins on shutdown or uninstall.

### Installing plugins

Clients manage plugins through four methods. The daemon does all filesystem work; the client only passes the path of the package on the daemon host.

| Method | Params → Result | Behavior |
|---|---|---|
| `inspect_plugin` | `{ path }` → `{ manifest, installed_version? }` | Validates the package as `install_plugin` would, without installing. Lets a client show a confirmation first. |
| `install_plugin` | `{ path }` → `{ plugin, previous_version? }` | Validates, extracts into `<config dir>/plugins/<id>/` and starts the plugin. An already-installed id is **replaced** (upgrade). Responds right after spawning (status normally `starting`). |
| `list_plugins` | `{}` → `{ plugins }` | Every installed plugin as `InstalledPlugin { manifest, status, error? }`, with `status` one of `starting`, `running`, `stopped`, `error`. |
| `uninstall_plugin` | `{ id }` → `{}` | Stops the process and deletes the folder. Bindings to its actions are kept (orphaned) and work again if the plugin is reinstalled. |

Both `inspect_plugin` and `install_plugin` reject a package that has no entrypoint for the daemon host's OS, so a plugin that can't run is never installed.

## Input colors (RGB)

A hardware-agnostic way to light up keys, independent of each device's lighting protocol:

- **Capability.** `list_devices` marks each input that has an RGB LED with `rgb: true` (absent means no LED). Clients never need to know the hardware.
- **Color format.** `Color` is a `#RRGGBB` hex string, accepted in any case and returned lowercase by the daemon. `#000000` turns the LED off.
- **Colors belong to profiles.** `Profile.colors` (and `ExportedProfile.colors`) is a list of `InputColor { device_id, input_id, color }`. When a profile becomes active, the daemon repaints every RGB input with that profile's colors; an RGB input without an entry is turned off.
- **Setting a color.** `set_input_color { device_id, input_id, color } → {}` writes the color into the **active** profile and paints it on the device right away (same scope as `set_binding`). The daemon rejects unknown inputs and inputs without an LED.
- **Reading colors.** `Input.color` in `list_devices` is the color the active profile paints on that input; absent means off.
- **From a binding.** The built-in `set_color` action (`SetColorActionParams { color, input_id?, device_id?, persist? }`) paints an LED when a binding fires. Without `input_id` it paints the input that fired the action (`device_id` defaults to that device and is only valid with `input_id`). By default the change is transient: the profile's colors are untouched and come back when a profile becomes active or the device reconnects. With `persist: true` it also writes the color into the active profile, like `set_input_color`. To change several keys at once, use a `macro` with several `set_color` steps.

Lighting effects (breathing, rainbow, ...), batch updates and plugin access to LEDs are out of scope for now; they can be added without breaking this contract.

## Device layout and rotation

Clients can draw any device with its physical layout, not just a known model:

- **Layout.** `Input.layout` is an `InputLayout { x, y, w?, h? }` in key units (1 = one standard key; fractions allowed; `w`/`h` default to 1), the same model as QMK/VIA `info.json`. Coordinates are in the device's **canonical orientation**: origin at the top-left, `y` growing downwards. The shape comes from `kind` (key = rectangle, encoder = circle). If any input of a device lacks a layout, clients fall back to a view without positions (e.g. a list).
- **Labels.** `Input.label` is a fixed name (e.g. `Enter`, `Play`) shown as-is in any orientation. Without one, clients name inputs by position: numbered per kind in reading order of the current, rotated view (by each input's top-left corner, `y` first, then `x`), so `Key 1` is always the top-left key as the device sits on the desk. Without a complete layout, inputs are numbered per kind in the order `list_devices` returns them.
- **Rotation.** `Device.rotation` is `0`, `90`, `180` or `270` degrees clockwise applied to the canonical layout (absent means `0`). It is set with `set_device_rotation { device_id, rotation } → {}` and stored **per device, not per profile**. It is presentation only: bindings and colors stay tied to the input id.

## Consuming from Go

The generated Go types are published as a submodule under [`go/`](./go) so any consumer can pull them in:

```bash
go get github.com/JoniDG/keyforge-protocol/go/protocol@latest
```

```go
import "github.com/JoniDG/keyforge-protocol/go/protocol"
```

### Versioning by tags

Because the module lives in a subdirectory, release tags are prefixed with the path: `go/vX.Y.Z` (e.g. `go/v0.1.0`). Pin to a specific release with:

```bash
go get github.com/JoniDG/keyforge-protocol/go/protocol@v0.1.0
```

Schema-major bumps (the `/v1/` segment in `$id`) and Go-module-major bumps are independent — the latter follows Go's [SemVer rules](https://go.dev/ref/mod#major-version-suffixes).

### Regenerating locally

```bash
make generate-go             # writes go/protocol/types.go
(cd go && go build ./...)    # sanity-check the module compiles
```

CI runs both steps and fails the build if `git diff --exit-code go/` is dirty — i.e. someone changed a schema without committing the regenerated types.

## Consuming from TypeScript

The generated TypeScript types are published as an npm package at [`ts/`](./ts), named `@jdg-keyforge/protocol`. The package is types-only — every export is a type alias or an interface; the compiled `.js` artifacts are empty modules.

While the package is unpublished, KeyForge workspace consumers install it from the source tree:

```bash
npm install file:../keyforge-protocol/ts
```

```ts
import type {
  Envelope,
  Request,
  Response,
  Device,
  Input,
  InputEvent,
  MethodHello,
  MethodListActions,
  MethodListDevices,
  EventInput,
} from '@jdg-keyforge/protocol';
```

The root barrel re-exports shared types from `common` and `envelope`, plus the top-level `Method*` / `Event*` type from each method and event file. Inner payload shapes are reachable through the parent type (e.g. `MethodListDevices['result']['devices']`).

### Versioning by tags

Mirroring the Go submodule, TS releases are tagged with the path prefix: `ts/vX.Y.Z` (e.g. `ts/v0.1.0`). Schema-major bumps (the `/v1/` segment in `$id`) drive a major bump in both packages; non-breaking schema additions bump only the minor/patch.

### Regenerating locally

```bash
make generate-ts             # writes ts/src/*
make build-ts                # tsc → ts/dist/ (.d.ts + .js)
```

CI runs both and fails the build if `git diff --exit-code ts/src/` is dirty.

## Versioning

Each schema declares an `$id` whose path includes a major version (`/v1/`). Breaking changes bump the major version. Clients announce the version they implement in the `hello` request; servers either accept it or close the connection with `UNSUPPORTED_PROTOCOL_VERSION`.

## License

[Apache 2.0](./LICENSE) — Copyright (c) 2026 Jonathan Daniel Gomez.
