# Release 1.0.2

Tag: `v1.0.2`
Generated: 2026-04-10

## Summary

- Added Mercurial-style `incoming` and `outgoing` views plus a guarded `sync -Push` workflow for refreshing stale PR branches safely.
- Added `sync -DryRun` so fetch, update, and push behavior can be previewed before TOI changes anything.
- Expanded the guided bisect workflow with JSON output, completion state, persisted logs, and an end-to-end smoke harness.
- Hardened sync, install, and CI behavior around interactive SSH prompts, signed PowerShell profiles, and GitHub auth edge cases.

## Commits

- 23b72da feat(sync): add dry-run preview and stale PR guidance
- 3116069 ux(sync): show success after interactive push
- 669c248 fix(sync): refresh tracking summary after push
- be25282 fix(sync): retry interactive fetch and correct tracking counts
- 8204f97 feat(sync): add guarded sync -Push workflow
- 0586d44 feat(sync): add incoming and outgoing commands
- 60f4d3c test(bisect): add end-to-end smoke harness
- 1529b26 feat(bisect): preserve and expose bisect logs
- 68a181e fix(bisect): handle detached head and completed sessions
- ecc6613 feat(bisect): surface completed culprit and reset guidance
- 1452f6d feat(bisect): add json output and stronger session validation
- ecfd963 feat(bisect): add guided bisect workflow
- 3820bcd ux(cli): prefer installed toi command in guidance
- 6050b0a fix(install): show correct reload command for fallback profile
- 0e1cdf9 fix(install): avoid modifying signed profiles
- c098a6f fix(ci): treat missing GH_TOKEN as unavailable gh auth
