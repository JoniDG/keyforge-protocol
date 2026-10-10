# jdg-keyforge-protocol

> Python types for the [KeyForge](https://github.com/JoniDG/keyforge) WebSocket protocol, generated from the canonical JSON Schema contracts in this repository.

This package contains only `TypedDict`s and type aliases, with no runtime dependencies. It mirrors the TypeScript package [`@jdg-keyforge/protocol`](https://www.npmjs.com/package/@jdg-keyforge/protocol) and the Go submodule at `github.com/JoniDG/keyforge-protocol/go/protocol`.

Requires Python 3.15+ (it uses PEP 728 closed `TypedDict`s from the standard library).

## Install

```bash
uv add jdg-keyforge-protocol      # or: pip install jdg-keyforge-protocol
```

## Usage

```python
import json

from keyforge_protocol import ActionInvokedData, HelloParams, PluginLaunchInfo

hello: HelloParams = {
    "protocol_version": "1",
    "client": {"name": "dev.example.counter", "version": "0.1.0"},
}

def on_action(data: ActionInvokedData) -> None:
    print(data["action"]["id"], data["action"]["params"])
```

The package root re-exports:

- every shared type from `common` and `envelope` (`InputEvent`, `PluginManifest`, `PluginLaunchInfo`, `Error`, ...);
- `Method<Name>` plus `<Name>Params` / `<Name>Result` for each method (e.g. `MethodHello`, `HelloParams`, `HelloResult`);
- `Event<Name>` plus `<Name>Data` for each event (e.g. `EventActionInvoked`, `ActionInvokedData`);
- types local to one method keep their schema name (`PeerInfo`, `ActionDescriptor`); other nested objects are prefixed with the method or event name (`ActionInvokedAction`);
- `JsonValue` / `JsonObject`, used for open objects such as `Action.params` and `Error.details`.

Types are static only: nothing is validated at runtime. Validate untrusted JSON against the schemas if you need to.

## Versioning

Versioned together with the Go submodule and the TS package, with tags `py/vX.Y.Z`. A breaking schema change bumps the schema's `/v1/` path and the major version of every package.

## Local regeneration

The contents of `src/keyforge_protocol/` are auto-generated. From the repository root:

```bash
make generate-py   # regenerate
make check-py      # mypy --strict + contract tests
make build-py      # sdist + wheel into py/dist/
```

## License

[Apache 2.0](./LICENSE) — Copyright (c) 2026 Jonathan Daniel Gomez.
