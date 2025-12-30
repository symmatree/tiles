When writing code or config,

- prefer short code.
- Do not restate defaults unless they are very important for the operation.
- do not build "just in case" customizability; prefer a single path and simplicity.

When you find yourself writing "if X is the case" consider whether X is already known,
or if it should be a design decision for the user, rather than avoiding the decision
with a handwave. As an example "# Backup Terraform state (if using remote state)" is
bad because you have access to the full Terraform config, you don't need to give generic
advice or treat it as a conditional.

When working with infrastructure as code,

- All changes to the system should be applied through IaC via the github workflows.
- use CLI and imperative tools for debugging but not to make changes.
- do not apply anything without my explicit permission.

When asked to investigate something, prefer to iterate one layer of troubleshooting
at a time, with the user, rather than writing a multi-stage script with many layered
assumptions. Discover the actual situation rather than writing conditional logic and
fallbacks. Aim to fail fast and clearly, not to muddle through without understanding
the underlying issues.
