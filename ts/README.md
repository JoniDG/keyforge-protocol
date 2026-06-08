# @jdg-keyforge/protocol

> TypeScript types for the [KeyForge](https://github.com/JoniDG/keyforge) WebSocket protocol, generated from the canonical JSON Schema contracts in this repository.

This package contains only type declarations — there is no runtime code. It mirrors the Go submodule published at `github.com/JoniDG/keyforge-protocol/go/protocol`.

## Install

```bash
npm install @jdg-keyforge/protocol
```

While the package is unpublished, consumers in the KeyForge workspace can install it directly from the source tree:

```bash
npm install file:../keyforge-protocol/ts
```

## Usage

```ts
import type {
  Envelope,
  Request,
  Response,
  Event,
  Device,
  InputEvent,
  MethodHello,
  MethodListDevices,
  EventInput,
} from '@jdg-keyforge/protocol';
```

The root `index` re-exports shared types from [`common`](./src/common.ts) and [`envelope`](./src/envelope.ts) plus the top-level `Method*` / `Event*` types for each method and event. Inner payload shapes (e.g. `MethodListDevices['result']`) are reachable through the parent type.

For schema definitions and the wire-protocol overview, see the [repository root README](../README.md).

## Versioning

This package is versioned independently from the schema's `/v1/` path and from the Go submodule:

| Artifact | Source of truth | Tag |
|---|---|---|
| Schema major | `$id` path (`.../v1/...`) | — |
| Go submodule | [`go/protocol/`](../go/protocol) | `go/vX.Y.Z` |
| TS package | [`ts/`](.) | `ts/vX.Y.Z` |

A breaking schema change bumps `/v1/` to `/v2/` *and* the major version of both packages. Non-breaking schema additions bump only the minor/patch of each package.

## Local regeneration

The contents of `src/` are auto-generated from the JSON Schemas. To regenerate after editing a schema, run from the repository root:

```bash
make generate-ts
```

Then build the package:

```bash
cd ts && npm install && npm run build
```

CI fails the build if `git diff --exit-code ts/src/` is dirty — i.e. someone changed a schema without committing the regenerated types.

## License

[Apache 2.0](./LICENSE) — Copyright (c) 2026 Jonathan Daniel Gomez.
