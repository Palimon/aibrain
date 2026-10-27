# Triage labels

Read [labels.json](labels.json) for the mapping from canonical `role` to actual label `name`, plus its color and description. That file is the source of truth for bootstrap and the skills. This repo uses the default names.

| Role | Meaning |
|---|---|
| `bug` | Something is broken |
| `enhancement` | New feature or improvement |
| `needs-triage` | Maintainer needs to evaluate the issue |
| `needs-info` | Waiting on the reporter for more information |
| `ready-for-agent` | Fully specified and ready for an agent to implement |
| `ready-for-human` | Requires human implementation |
| `wontfix` | Will not be implemented |

Triage assigns one category, `bug` or `enhancement`, and one state. Preserve unrelated labels. If state labels conflict, ask before changing them. `to-spec` applies `ready-for-agent` directly to its completed spec.

Bootstrap and `aibrain-labels .` create missing labels and repair configured colors and descriptions. They preserve labels outside the manifest and do not label existing issues or run triage.
