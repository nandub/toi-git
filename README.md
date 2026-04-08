# TOI Git

TOI Git is a PowerShell workflow assistant for modern Git. It keeps raw Git visible, adds typed branch workflows, and gives you practical guidance for daily branch, review, release, and automation work.

## Start Here

The shortest useful flow looks like this:

```powershell
.\toi.ps1 start feature login-form
.\toi.ps1 status
.\toi.ps1 ship
.\toi.ps1 publish
.\toi.ps1 open pr
```

That covers the core TOI path:

- create a typed branch
- inspect local state
- check whether the branch is ready
- publish it to the remote
- open the PR path

## Quickstart

Run TOI Git from inside a Git repository.

```powershell
.\toi.ps1 status
.\toi.ps1 dashboard
.\toi.ps1 next
```

If you are starting new work:

```powershell
.\toi.ps1 start feature login-form
.\toi.ps1 note set "Prepare login form PR"
.\toi.ps1 save
.\toi.ps1 ship
.\toi.ps1 publish
```

If you just want a fast repo check:

```powershell
.\toi.ps1 doctor
.\toi.ps1 report
.\toi.ps1 self-check
```

## Command Groups

### Everyday Flow

- `start`: create a typed branch like `feature/login`
- `status`: compact branch and working tree summary
- `summary`: recent commit history plus working tree overview
- `save`: stage everything and create a checkpoint commit
- `commit`: create a commit with a message
- `undo`: undo the last commit with a safe reset mode
- `sync`: fetch remotes and show branch tracking state
- `next`: show the most likely next action

### Review And PR Flow

- `doctor`: inspect repo state and suggest next actions
- `ship`: assess whether a branch is ready for push or PR
- `publish`: push the current branch and print or open the PR path
- `open`: open the repo, branch, compare view, or PR path in a browser
- `note`: store a local branch note in `.git`

### Release And Stack Flow

- `stack`: create or restack dependent branches
- `release`: start releases, scaffold notes, and create tags
- `hotfix`: create hotfix branches from the default branch
- `worktree`: list or add Git worktrees
- `branch-clean`: list merged local branches and optionally delete them

### Automation And Diagnostics

- `dashboard`: consolidated workflow overview
- `report`: workflow report in markdown or JSON
- `schema`: JSON contract summary for automation consumers
- `self-check`: lightweight local verification for TOI Git

## Common Flows

### Start A Feature

```powershell
.\toi.ps1 start feature login-form
.\toi.ps1 note set "Prepare login form PR"
.\toi.ps1 status
```

### Publish A Branch

```powershell
.\toi.ps1 ship
.\toi.ps1 publish
.\toi.ps1 open pr
```

### Cut A Release

```powershell
.\toi.ps1 release start 1.4.0
.\toi.ps1 release notes 1.4.0
.\toi.ps1 release tag 1.4.0
```

### Inspect Repo State In CI Or Scripts

```powershell
.\toi.ps1 status -Json
.\toi.ps1 report -Json
.\toi.ps1 schema -Json
.\toi.ps1 self-check -Json
```

## Automation And Contracts

These commands support `-Json`:

- `status -Json`
- `dashboard -Json`
- `next -Json`
- `doctor -Json`
- `ship -Json`
- `publish -Json`
- `release ... -Json`
- `self-check -Json`
- `report -Json`
- `schema -Json`

Use them this way:

- `status -Json` for lightweight branch and working tree state
- `dashboard -Json` for a richer workflow snapshot plus next actions
- `report -Json` for a CI-friendly workflow summary
- `schema -Json` for the current JSON contract surface
- `schema -Json -Snapshot` for the stable committed contract form without timestamps
- `self-check -Json` for machine-readable local verification results

The built-in `self-check` validates core JSON outputs against the declared contracts from `schema`, so automation drift is caught locally before CI.
The contract version is tracked in [contracts/contract-version.txt](C:\Users\ferna\development\code\powershell\Codex\Toi\contracts\contract-version.txt), and the committed schema baseline lives in [contracts/toi-schema.json](C:\Users\ferna\development\code\powershell\Codex\Toi\contracts\toi-schema.json).

GitHub Actions currently does this on pushes to `main` and on pull requests:

- runs the built-in self-check
- uploads the self-check JSON artifact
- uploads workflow report artifacts in markdown and JSON
- uploads the JSON contract artifact from `schema -Json`
- publishes the markdown workflow report as the job summary

## Config

TOI Git reads `toi.json` from the repository root.

Default shape:

```json
{
  "defaultBranch": "main",
  "branchTypes": ["feature", "fix", "hotfix", "release", "chore"],
  "syncStrategy": "rebase",
  "protectBranches": ["main"],
  "commitConvention": "optional",
  "commitScopes": [],
  "branchNoteRequired": false,
  "qualityGateMode": "warn",
  "validationCommands": [],
  "requirePublishedForPr": true,
  "dashboardSections": ["branch", "publish", "stack", "gates", "next"],
  "releaseTagPrefix": "v",
  "releaseNotesFile": "CHANGELOG.md",
  "releaseVersionPattern": "^\\d+\\.\\d+\\.\\d+$",
  "releaseBranches": true,
  "stackedBranches": true
}
```

Important fields:

- `qualityGateMode`: `warn` or `block`
- `commitConvention`: `off`, `optional`, or `required`
- `commitScopes`: allowed scopes for conventional commits
- `branchNoteRequired`: require a local note on non-default branches
- `validationCommands`: PowerShell commands to run before `ship` and `publish`
- `requirePublishedForPr`: require the branch to be pushed before `open pr`
- `dashboardSections`: controls which sections appear in `dashboard`
- `releaseTagPrefix`: prefix used for release tags like `v1.2.3`
- `releaseNotesFile`: file generated by `release notes`
- `releaseVersionPattern`: regex used to validate release versions

Example with blocking validation:

```json
{
  "defaultBranch": "main",
  "branchTypes": ["feature", "fix", "hotfix", "release", "chore"],
  "syncStrategy": "rebase",
  "protectBranches": ["main"],
  "qualityGateMode": "block",
  "validationCommands": [
    ".\\toi.ps1 summary"
  ],
  "requirePublishedForPr": true,
  "releaseBranches": true,
  "stackedBranches": true
}
```

## Reference

More examples:

```powershell
.\toi.ps1 publish -DryRun
.\toi.ps1 publish -Pr
.\toi.ps1 dashboard
.\toi.ps1 next
.\toi.ps1 branch-clean
.\toi.ps1 branch-clean -Apply
.\toi.ps1 undo -Soft
.\toi.ps1 open
.\toi.ps1 open branch
.\toi.ps1 open compare
.\toi.ps1 worktree list
.\toi.ps1 worktree add ..\Toi-feature feature/demo
.\toi.ps1 stack new api-client
.\toi.ps1 stack restack
.\toi.ps1 stack parent
.\toi.ps1 hotfix start payment-timeout
```

TOI Git stores stack parent metadata and branch notes under the local `.git` directory so this workflow state does not pollute tracked files.

There is also a lightweight wrapper at [tests/self-check.ps1](C:\Users\ferna\development\code\powershell\Codex\Toi\tests\self-check.ps1) for running the built-in verification flow.
