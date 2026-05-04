# Hooks — keyforge-protocol

Shell scripts referenced from `.claude/settings.json` go here.

This repo has no source code to format, so no hooks are configured by default. Possible additions later:

- Validate schemas after Edit/Write to `schemas/**/*.json` (run `make validate`).
- Auto-regenerate types after schema changes.

Format reference: see `settings.json` of any repo for the JSON shape (`hooks.PostToolUse`, etc).
