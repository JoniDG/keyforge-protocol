"""Contract checks for the generated types.

mypy --strict checks each literal below against its type; at runtime, each
literal must equal the example of the same shape in examples/, which ajv
validates against the schemas. Together they catch a generator change that
would type the protocol differently from what the daemon sends.
"""

import json
import unittest
from pathlib import Path

from keyforge_protocol import (
    ActionInvokedData,
    Error,
    HelloParams,
    HelloResult,
    InputEvent,
    PluginLaunchInfo,
    PluginManifest,
)

EXAMPLES = Path(__file__).resolve().parents[2] / "examples"

LAUNCH_INFO: PluginLaunchInfo = {
    "plugin_id": "dev.jonidg.spotify",
    "ws_url": "ws://127.0.0.1:53817/ws?token=3f9c2a7e1b",
    "protocol_version": "1",
}

HELLO_PARAMS: HelloParams = {
    "protocol_version": "1",
    "client": {"name": "keyforge-desktop", "version": "0.1.0"},
}

HELLO_RESULT: HelloResult = {
    "protocol_version": "1",
    "server": {"name": "keyforged", "version": "0.1.0"},
}

ERROR: Error = {
    "code": "UNSUPPORTED_PROTOCOL_VERSION",
    "message": "Server speaks protocol_version 1; client requested 2.",
    "details": {"supported": ["1"], "requested": "2"},
}

INPUT_EVENT: InputEvent = {
    "device_id": "VID_6D82_PID_DC83",
    "kind": "encoder",
    "input_id": "encoder_0",
    "action": "rotate_cw",
    "timestamp_ms": 1790000000000,
}

ACTION_INVOKED: ActionInvokedData = {
    "context": "b7e1c04a9f",
    "action": {"id": "volume", "params": {"step": "5"}},
    "input": INPUT_EVENT,
}

MANIFEST: PluginManifest = {
    "manifest_version": 1,
    "id": "dev.jonidg.spotify",
    "name": "Spotify",
    "version": "0.1.0",
    "protocol_version": "1",
    "author": "JoniDG",
    "description": "Control Spotify playback from your keypad.",
    "homepage": "https://github.com/JoniDG/keyforge-plugin-spotify",
    "category": "Audio",
    "icon": "assets/icon.png",
    "entrypoint": {
        "darwin": {"path": "bin/spotify-darwin"},
        "linux": {"path": "bin/spotify-linux"},
        "windows": {"path": "bin/spotify.exe"},
    },
    "actions": [
        {
            "id": "play_pause",
            "name": "Play / Pause",
            "params": [
                {
                    "name": "volume_encoder",
                    "label": "Volume encoder",
                    "type": "input",
                    "required": False,
                    "input_filter": {"kinds": ["encoder"]},
                }
            ],
        },
        {
            "id": "volume",
            "name": "Volume",
            "description": "Turn the encoder to change Spotify's volume.",
            "inputs": ["encoder"],
            "params": [
                {
                    "name": "step",
                    "label": "Step (%)",
                    "type": "string",
                    "required": False,
                    "placeholder": "5",
                }
            ],
        },
    ],
}


def example(relative: str) -> object:
    return json.loads((EXAMPLES / relative).read_text())


class ContractTest(unittest.TestCase):
    def test_literals_match_examples(self) -> None:
        cases: list[tuple[str, object]] = [
            ("files/plugin_launch_info.json", LAUNCH_INFO),
            ("files/plugin_manifest.json", MANIFEST),
            ("methods/hello.json", {"params": HELLO_PARAMS, "result": HELLO_RESULT}),
            ("events/action_invoked.json", {"data": ACTION_INVOKED}),
            ("frames/error_response.json", ERROR),
        ]
        for relative, literal in cases:
            with self.subTest(example=relative):
                expected = example(relative)
                if relative.startswith("frames/"):
                    assert isinstance(expected, dict)
                    expected = expected["error"]
                self.assertEqual(expected, literal)


if __name__ == "__main__":
    unittest.main()
