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

Plugins are distributed as a **`.keyforgeplugin`** file: a zip archive with `manifest.json` at its root (no wrapping folder) plus every file the manifest references. The daemon installs it by extracting the archive into `<config dir>/plugins/<id>/`, taking the id from the manifest. All file paths in the manifest (`icon`, and entrypoint paths containing `/`) are relative to the plugin root, use `/` as separator (also on Windows), and must stay inside the plugin root: the daemon rejects `..` segments and any path or archive entry that escapes it.

## Plugin runtime

How the daemon runs an installed plugin and talks to it:

1. **Launch.** The daemon spawns the manifest's `entrypoint` for the current OS and sets the `KEYFORGE_PLUGIN_INFO` environment variable to a JSON `PluginLaunchInfo` (`plugin_id`, `ws_url`, `protocol_version`). An env var is used instead of CLI args so the auth token doesn't show up in the process list. See [`examples/files/plugin_launch_info.json`](examples/files/plugin_launch_info.json).
2. **Connect.** The plugin opens `ws_url`, which carries a **per-plugin token** distinct from the GUI's, and sends the regular `hello` with `client.name` set to its plugin id. The daemon identifies the plugin by its token; a `hello` whose name doesn't match is answered with `FORBIDDEN` and the connection is closed.
3. **Receive actions.** When a binding or macro step for `plugin.<plugin_id>.<action_id>` fires, the daemon sends the `action_invoked` event to that plugin's connection only, with an opaque `context` (stable per binding instance, so a plugin can keep per-instance state), the action id, its params and, when the trigger came from hardware, the `InputEvent` that fired it. Delivery is fire-and-forget: the daemon doesn't wait for the plugin.
4. **Permissions.** A plugin connection may only call `hello` and only receives its own `action_invoked` events (no `input` or GUI-facing events). Any other method is answered with error code `FORBIDDEN`.
5. **Exit.** A plugin must exit when its WebSocket connection closes. That's how the daemon stops plugins on shutdown or uninstall.

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
