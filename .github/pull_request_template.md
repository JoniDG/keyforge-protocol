<!--
Title format (Conventional Commits):
  feat: short description
  fix: short description
  chore: short description
  refactor: short description
  docs: short description
-->

## Summary

<!-- 1-3 sentences describing what this PR does and why. -->

## Changes

<!-- Bullet list of the technical changes. -->
- 

## Schema impact

<!-- Required if any schema changed. Otherwise: "No schema changes." -->
- [ ] No schema changes
- [ ] New schema added (non-breaking)
- [ ] Existing schema modified (BREAKING — requires `$id` major bump)

## Test plan

- [ ] `make validate` passes
- [ ] `make generate` completes without errors (Go + TS types regenerate)
- [ ] Examples added/updated for any new or changed message

## Checklist

- [ ] Branch named `feature/...`, `fix/...`, `chore/...`, etc.
- [ ] Commits follow Conventional Commits (`feat:`, `fix:`, `chore:`...)
- [ ] No `additionalProperties: true` introduced
- [ ] CLAUDE.md updated if conventions changed
- [ ] No identity leakage (defensive grep clean)

## Notes for reviewer (optional)

<!-- Anything tricky, context, or follow-ups. -->
