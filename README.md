# TOI Git

TOI Git is a small PowerShell CLI for common Git workflows with cleaner output and a few safe shortcuts.

## Commands

- `status`: compact branch and working tree summary
- `summary`: recent commit history plus working tree overview
- `sync`: fetch remotes and show branch tracking state
- `commit`: create a commit with a message
- `branch-clean`: list merged local branches and optionally delete them

## Usage

```powershell
.\toi.ps1 status
.\toi.ps1 summary
.\toi.ps1 sync
.\toi.ps1 commit "Add branch cleanup helper"
.\toi.ps1 branch-clean
.\toi.ps1 branch-clean -Apply
```

Run the command from inside a Git repository.
