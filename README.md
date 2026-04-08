# TOI Git

TOI Git is a small PowerShell CLI for common Git workflows with cleaner output and a few safe shortcuts.

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

## Usage

```powershell
.\toi.ps1 status
.\toi.ps1 summary
.\toi.ps1 sync
.\toi.ps1 commit "Add branch cleanup helper"
.\toi.ps1 branch-clean
.\toi.ps1 branch-clean -Apply
.\toi.ps1 save
.\toi.ps1 undo
.\toi.ps1 undo -Soft
.\toi.ps1 open
.\toi.ps1 worktree list
.\toi.ps1 worktree add ..\Toi-feature feature/demo
```

Run the command from inside a Git repository.
