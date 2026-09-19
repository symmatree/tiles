# One-time state plumbing for the move to modules/github-repo. Delete this file
# once the apply that consumes it has landed.
#
# `moved` covers the three repositories that were already managed as inline
# resource blocks; `import` adopts the two that existed on GitHub but had never
# been under Terraform. Without the imports, Terraform would try to create
# repositories that already exist and fail.

moved {
  from = github_repository.tiles
  to   = module.repo["tiles"].github_repository.this
}

moved {
  from = github_repository_ruleset.tiles-main
  to   = module.repo["tiles"].github_repository_ruleset.main
}

moved {
  from = github_repository_ruleset.tiles-tags
  to   = module.repo["tiles"].github_repository_ruleset.tags[0]
}

moved {
  from = github_repository.polisher
  to   = module.repo["polisher"].github_repository.this
}

moved {
  from = github_repository_ruleset.polisher-main
  to   = module.repo["polisher"].github_repository_ruleset.main
}

moved {
  from = github_repository_ruleset.polisher-tags
  to   = module.repo["polisher"].github_repository_ruleset.tags[0]
}

moved {
  from = github_repository.fables
  to   = module.repo["fables"].github_repository.this
}

moved {
  from = github_repository_ruleset.fables-main
  to   = module.repo["fables"].github_repository_ruleset.main
}

moved {
  from = module.secret_onepassword_sa_token
  to   = module.secret_onepassword_sa_token["tiles"]
}

moved {
  from = module.secret_onepassword_sa_token_polisher
  to   = module.secret_onepassword_sa_token["polisher"]
}

import {
  to = module.repo["coordinator"].github_repository.this
  id = "coordinator"
}

import {
  to = module.repo["dotfiles-symm"].github_repository.this
  id = "dotfiles-symm"
}
