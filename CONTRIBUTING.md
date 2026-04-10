# Contributing

## Workflow

TOI Git is maintained as a PowerShell-first CLI.

Normal local loop:

```powershell
.\toi.ps1 status
.\tests\self-check.ps1
```

`.\toi.ps1 start ...` should stay local-first. Do not make branch creation depend on a remote fetch or live GitHub auth unless that behavior is explicitly opt-in.

If you change JSON-producing commands or contract descriptions:

```powershell
.\toi.ps1 schema -WriteSnapshot
.\tests\self-check.ps1
```

If you change the GitHub Actions workflow or report output:

```powershell
.\tests\ci-artifacts.ps1
```

If you change the bisect workflow:

```powershell
.\tests\bisect-smoke.ps1
.\tests\self-check.ps1
```

## GitHub-Aware Commands

Some commands need a real GitHub context:

- `.\toi.ps1 pr ...`
- `.\toi.ps1 review`
- `.\toi.ps1 open pr`
- `.\toi.ps1 release publish ...`

For those paths:

- `gh.exe` must be available on `PATH`
- `gh auth status` should be clean
- the current branch should have a live PR when testing PR flows
- on branches without a PR, TOI should report a normal informational state instead of surfacing raw `gh` errors

Local smoke coverage intentionally avoids requiring a live authenticated PR so CI stays stable.

Useful live smoke path:

```powershell
.\toi.ps1 start feature <name>
.\toi.ps1 ship
.\toi.ps1 publish -Pr
.\toi.ps1 pr status
.\toi.ps1 pr checks -Required
.\toi.ps1 pr gate
.\toi.ps1 review
```

## Contracts

The machine-readable contract is tracked in:

- [contracts/contract-version.txt](C:\Users\ferna\development\code\powershell\Codex\Toi\contracts\contract-version.txt)
- [contracts/toi-schema.json](C:\Users\ferna\development\code\powershell\Codex\Toi\contracts\toi-schema.json)

Rules:

- refresh the snapshot intentionally with `.\toi.ps1 schema -WriteSnapshot`
- bump the version intentionally with `.\toi.ps1 schema -BumpVersion patch|minor|major`
- do not hand-edit the schema snapshot unless you are fixing generation itself

## CI Notes

GitHub Actions runs on `windows-latest` and currently captures:

- self-check JSON
- workflow report markdown and JSON
- schema JSON

The workflow now invokes TOI through explicit `pwsh -File` calls. If a CI capture step fails, reproduce it locally with [tests/ci-artifacts.ps1](C:\Users\ferna\development\code\powershell\Codex\Toi\tests\ci-artifacts.ps1) before changing the workflow again.

## Style

- prefer small commits with one clear purpose
- keep raw Git visible; avoid magic state when a plain Git command would be clearer
- use `apply_patch` for manual file edits
- keep user-facing output concise and scan-friendly
