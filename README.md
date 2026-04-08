# TOI Git

TOI Git is a PowerShell workflow assistant for modern Git. It keeps raw Git visible, adds typed branch workflows, and provides safety checks for day-to-day shipping.

## Commands

- `status`: compact branch and working tree summary
- `summary`: recent commit history plus working tree overview
- `sync`: fetch remotes and show branch tracking state
- `commit`: create a commit with a message
- `branch-clean`: list merged local branches and optionally delete them
- `save`: stage everything and create a checkpoint commit
- `undo`: undo the last commit with a safe reset mode
- `open`: open the repository remote in a browser
- `worktree`: list or add Git worktrees
- `start`: create a typed branch like `feature/login`
- `doctor`: inspect repo state and suggest next actions
- `ship`: assess whether a branch is ready for push or PR
- `publish`: push the current branch and print/open the PR path
- `publish`: push the current branch and print/open the PR path
- `stack`: create or restack dependent branches
- `release`: create release branches from the default branch
- `hotfix`: create hotfix branches from the default branch

## Workflow Shape

- Everyday flow: `start`, `sync`, `save`, `ship`, `undo`
- PR flow: `publish`, `open pr`, remote-aware `doctor`
- Team structure: typed branch names, protected branch awareness, default branch policy
- Advanced flow: stack branches, release branches, hotfix branches, worktrees

## Config

TOI Git reads `toi.json` from the repository root.

```json
{
  "defaultBranch": "main",
  "branchTypes": ["feature", "fix", "hotfix", "release", "chore"],
  "syncStrategy": "rebase",
  "protectBranches": ["main"],
  "commitConvention": "optional",
  "releaseBranches": true,
  "stackedBranches": true
}
```

## Usage

```powershell
.\toi.ps1 status
.\toi.ps1 start feature login-form
.\toi.ps1 doctor
.\toi.ps1 ship
.\toi.ps1 publish
.\toi.ps1 publish -DryRun
.\toi.ps1 publish -Pr
.\toi.ps1 summary
.\toi.ps1 sync
.\toi.ps1 commit "Add branch cleanup helper"
.\toi.ps1 branch-clean
.\toi.ps1 branch-clean -Apply
.\toi.ps1 save
.\toi.ps1 undo
.\toi.ps1 undo -Soft
.\toi.ps1 open
.\toi.ps1 open branch
.\toi.ps1 open compare
.\toi.ps1 open pr
.\toi.ps1 worktree list
.\toi.ps1 worktree add ..\Toi-feature feature/demo
.\toi.ps1 stack new api-client
.\toi.ps1 stack restack
.\toi.ps1 release start 1.4.0
.\toi.ps1 hotfix start payment-timeout
```

Run the command from inside a Git repository.
