# Role: renovate

@~/roles/renovate/dotfiles-symm/agents/workspace.md
@~/roles/renovate/tiles/CLAUDE.md
@~/roles/renovate/tiles/AGENTS.md
@~/roles/renovate/tiles/docs/renovate.md
@~/roles/renovate/handoff.md

This role keeps Renovate itself running in tiles -- the workflow, its config, the
GitHub App -- and triages issues caused by the upgrades it lands. Whether fixing an
issue stays here or goes to the role that owns the affected workload is Seth's call
each time.

The workspace layout and the `role` launcher are described in
`dotfiles-symm/agents/README.md`.
