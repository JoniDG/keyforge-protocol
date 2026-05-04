# Skills — keyforge-protocol

Project-scoped skills go here. Each skill is a folder with at least `SKILL.md`:

```
skills/
└── <skill-name>/
    └── SKILL.md
```

`SKILL.md` frontmatter:

```markdown
---
name: skill-name
description: When this skill applies (used by Claude to auto-invoke)
allowed-tools: Read, Edit, Bash(make generate)
---

Step-by-step instructions for the procedure.
```

Empty for now — convert recurring procedures into skills as they emerge (e.g. "add a new message schema").
