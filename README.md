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
  common.schema.json     # shared types: Device, DeviceID, InputEvent, Action, Binding, ...
  envelope.schema.json   # request / response / event frames
  methods/               # one schema per RPC method (params + result)
    hello.schema.json
    list_devices.schema.json
    set_binding.schema.json
  events/                # one schema per server-to-client event (data)
    input.schema.json
examples/
  frames/                # complete envelope frames (validated against envelope.schema.json)
  methods/               # logical { params, result } payloads (validated against the method schema)
  events/                # logical { data } payloads (validated against the event schema)
dist/                    # generated Go + TS types (git-ignored)
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

Generated types land in `dist/go/types.go` and `dist/ts/*.ts`. They are git-ignored — regenerate locally.

> **Note:** `make` automatically prepends `$(go env GOPATH)/bin` to `PATH`, so `go-jsonschema` is found even if you have not added `~/go/bin` to your shell `PATH`.

## Schema conventions

- `$id` paths mirror the filesystem (e.g. `https://keyforge.dev/schemas/v1/methods/hello.schema.json`).
- Cross-file `$ref`s use **file-relative paths** (`../common.schema.json#/$defs/Device`), so both `ajv` and `go-jsonschema` resolve them consistently.
- Method names and event names are **`snake_case`** (no `c2s_` / `s2c_` prefix — the envelope `type` already implies direction).
- `additionalProperties: false` on every object. `required` declared explicitly.

## Versioning

Each schema declares an `$id` whose path includes a major version (`/v1/`). Breaking changes bump the major version. Clients announce the version they implement in the `hello` request; servers either accept it or close the connection with `UNSUPPORTED_PROTOCOL_VERSION`.

## License

[Apache 2.0](./LICENSE) — Copyright (c) 2026 Jonathan Daniel Gomez.
