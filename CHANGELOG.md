# Current State

Release tag: none
Generated: 2026-04-08
Branch: `main`

## Summary

- Built `TOI Git` into a PowerShell workflow assistant for local Git, GitHub PR and review flows, release helpers, install and module packaging, contract-aware automation, and CI reporting.
- Added JSON output, schema snapshots, self-check coverage, and GitHub Actions artifact capture so the CLI works for both interactive use and automation.
- Added maintainer-focused docs and local CI reproduction helpers to make the project easier to operate and evolve.

## Commits

- 62968ee docs(maintainer): add ci reproduction and contribution guide
- c95f8fe workflow(ci): invoke TOI scripts explicitly in Actions
- 2606cb4 workflow(ci): emit report markdown to pipeline
- 1496798 workflow(github): add review summary command
- 4195490 workflow(ui): surface pr guidance in dashboard and next
- 9c4b62e workflow(github): add next-step recommendations to pr gate
- 81dee83 workflow(github): surface reviewer pressure in pr flows
- fc47db5 workflow(github): add pr gate readiness summary
- dc7bc56 workflow(github): add pr merge command
- fcfccdd workflow(github): add pr status, checks, and ready commands
- edfdc14 cli(packaging): add module install lifecycle
- 6738927 workflow(github): add gh-powered pr and release flows
- 4e63450 cli(dx): add install flow for PowerShell usage
- 94f1e9c docs(cli): prefer toi.ps1 in powershell guidance
- 396874b cli(dx): add toi launcher and shorten examples
- 9831c74 workflow(ui): surface contract status in daily views
- 13d2bb5 workflow(contract): add snapshot checks and version bump helpers
- d4806c7 workflow(contract): add schema snapshot refresh flow
- 847569f workflow(contract): add versioned schema snapshots
- a2d172e workflow(test): validate json payloads against schemas
- 55dc349 docs(readme): reorganize quickstart and workflow guides
- 191b1eb workflow(core): export json command schemas
- cb0a7d8 workflow(test): validate json command contracts
- 415390b workflow(report): add markdown and json workflow reports
- a902d15 workflow(ci): publish self-check summary and artifact
- 67fc60e workflow(core): add json output for doctor, ship, publish, and release
- 246da98 workflow(ci): run self-check in GitHub Actions
- d1ee1e0 workflow(core): add json output for automation
- 704edf3 workflow(core): add built-in self-check command
- 93fa255 workflow(ui): polish dashboard, next, and status views
- 97a9dfb Restore relaxed default policy settings
- 7c37b49 workflow(core): add branch notes and commit convention helpers
- 0a5dc19 Add release notes and tag workflows
- 51e975e Store stack metadata in .git
- ccef017 Add dashboard command and explicit stack metadata
- 08cad48 Add policy engine and quality gates
- b0d00d9 Fix Git subprocess status parsing
- 10b5962 Use Windows OpenSSH for Git subprocesses
- 07cff6d Add PR-aware publish workflow
- bdf095d Improve remote-aware doctor, ship, open, and sync
- 731f33a Add hybrid workflow assistant commands
- 92891ec Add save, undo, open, and worktree commands
- c55b213 Initial TOI Git scaffold
