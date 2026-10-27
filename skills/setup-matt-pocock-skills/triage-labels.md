# Triage labels

Read `labels.json` beside this file for the mapping from canonical `role` to actual label `name`, color and description. Retain only roles used by the installed skills when setting up a project.

| Role | Meaning |
|---|---|
| `bug` | Something is broken |
| `enhancement` | New feature or improvement |
| `needs-triage` | Maintainer needs to evaluate this issue |
| `needs-info` | Waiting on reporter for more information |
| `ready-for-agent` | Fully specified, ready for an agent |
| `ready-for-human` | Requires human implementation |
| `wontfix` | Will not be implemented |

When a skill mentions a role, use its label `name` from `labels.json`. Triage assigns one category and one state; `to-spec` applies `ready-for-agent` to a completed spec.

Change the manifest to use different label names. Run `aibrain-labels .` on GitHub after changes; bootstrap also synchronizes configured checkouts. Provisioning preserves unrelated labels and does not label existing issues or run triage.
