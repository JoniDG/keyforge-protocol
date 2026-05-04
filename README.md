# keyforge-protocol

> Wire protocol contracts for the [KeyForge](https://github.com/JoniDG/keyforge) ecosystem.

This repository defines the **JSON Schema** contracts shared between the KeyForge daemon, GUI and plugins. All messages travel as JSON over a local WebSocket. Strongly-typed Go and TypeScript bindings are generated automatically from the schemas.

## Status

🚧 **Pre-alpha.** APIs are not stable yet.

## Quickstart

```bash
# Install generators (one-time)
go install github.com/atombender/go-jsonschema@latest
npm install -g json-schema-to-typescript ajv-cli

# Generate Go and TS types from schemas
make generate

# Validate the example messages against their schemas
make validate
```

Generated types land in `dist/go/` and `dist/ts/`. They are git-ignored — regenerate locally.

## Layout

| Path | Purpose |
|---|---|
| `schemas/common.schema.json` | Shared types: `Action`, `InputEvent`, `Binding`, `DeviceID`, etc. |
| `schemas/messages/c2s_*.schema.json` | Client → server messages (GUI/plugin → daemon) |
| `schemas/messages/s2c_*.schema.json` | Server → client messages (daemon → GUI/plugin) |
| `examples/*.json` | Sample messages for smoke testing and documentation |

## Versioning

Each schema declares an `$id` that includes a version (e.g. `https://keyforge.dev/schemas/v1/...`). Breaking changes bump the major version.

## License

[Apache 2.0](./LICENSE) — Copyright (c) 2026 Jonathan Daniel Gomez.
