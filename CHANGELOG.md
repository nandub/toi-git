# Release 1.0.1

Tag: `v1.0.1`
Generated: 2026-04-08

## Summary

- Added a `version` command and `Get-ToiVersion` module export so installed TOI environments can report module, tag, and commit version state directly.
- Stabilized `self-check` around the new version flow, no-PR informational behavior, and GitHub auth detection so the local verification suite passes reliably again.

## Commits

- 3282e6b feat(version): add version command and stabilize self-check
