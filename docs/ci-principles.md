# CI/CD Principles

## Assertive, Not Adaptive

CI is not supposed to be adaptive; it is supposed to be assertive. A conditional about the state of the environment is almost always an error. Either we need to install a tool or we don't—we shouldn't look for it. Ditto for source files that we expect to read—don't write handlers for them being missing, just make sure it dies instead of accidentally continuing.

### Examples

**Bad:**
```bash
if command -v helm &>/dev/null; then
    helm template ...
else
    echo "Warning: helm not found"
fi
```

**Good:**
```bash
helm template ...
# If helm isn't installed, the script dies. That's correct.
```

**Bad:**
```bash
if [[ -f "config.yaml" ]]; then
    # use config
else
    echo "Warning: config.yaml not found, using defaults"
fi
```

**Good:**
```bash
# use config.yaml
# If it doesn't exist, the script dies. That's correct.
```

### Rationale

- **Fail fast**: If something is wrong, we want to know immediately, not silently continue with wrong behavior
- **Explicit dependencies**: If a script needs a tool or file, that dependency should be explicit in the setup, not hidden in conditionals
- **No silent failures**: Conditionals that check for existence often lead to scripts that appear to succeed but produce incorrect results
- **Easier debugging**: When a script fails because something is missing, the error is clear and actionable
