# CLAUDE.md -- tiles

What is particular to this repo. How to work with Seth is
[`agents/conduct.md`](https://github.com/symmatree/dotfiles-symm/blob/main/agents/conduct.md)
in dotfiles-symm, which every session on a machine set up by its
`ubuntu-zsh/install.sh` has loaded as `~/.claude/CLAUDE.md`. A session that does not
(one on claude.ai/code, say) should read it first.

- [`AGENTS.md`](AGENTS.md) -- the procedures to follow rather than reconstruct:
  branches and merging, regenerating `rendered.yaml`, the render diff, deploying,
  the charts Terraform installs.
- [`docs/index.md`](docs/index.md) -- the documentation.
- GitHub settings for this repo and the others -- merge mode, rulesets, required
  checks, secrets -- are Terraform in [`tf/bootstrap`](tf/bootstrap/README.md).
- `agents/<role>/` -- the packages of the agent roles homed here; see
  `agents/README.md` in dotfiles-symm.

ASCII only (straight quotes, `--` for em-dash).
