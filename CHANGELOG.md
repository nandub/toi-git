# Release 1.0.3

Tag: `v1.0.3`
Generated: 2026-05-06

## Summary

- Added PowerShell argument completion and made profile/module registration work with installed `toi` wrappers.
- Made completion and profile installation idempotent so repeated profile reloads or install updates do not duplicate behavior or profile blocks.
- Hardened `status`, `dashboard`, `doctor`, and `ship` for Windows PowerShell 5.1 strict behavior and detached `HEAD` checkouts.
- Added workflow-state guidance for conflict/rebase style repository states and an install update path for existing TOI installs.

## Commits

- f046ccd fix(workflow): harden daily commands for strict mode
- b60e0e5 fix(status): handle detached head and strict mode
- 87fcf61 fix(install): keep profile snippet idempotent
- 45ccdc5 fix(shell): make completion registration idempotent
- fb72df7 fix(shell): support completion in profile wrappers
- edb26f0 fix(shell): bind completion to wrapper arguments
- c5b3a81 feat(shell): add PowerShell completion support
- c9388f6 feat(workflow): add conflict guidance and install update
