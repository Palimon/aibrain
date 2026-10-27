---
name: apply-learnings
description: Apply retrospective findings and recurring agent corrections through code, automated checks, and enforced workflows. Use after retro, or when an agent keeps skipping a required step or breaking a rule.
---

# Apply learnings

Turn observed failures into changes that prevent recurrence. Prefer mechanisms that work even when the agent forgets the instruction.

## Steps

1. Read the retrospective or correction and its evidence. For each finding, identify the failed behavior, the required outcome, and the source that owns it. Use the current session when none is specified. If the evidence does not establish a failure, record the uncertainty instead of adding a permanent rule.

2. Inspect the existing implementation, commands, checks, and configuration. Repair an existing mechanism before adding another. Edit maintained sources rather than installed copies or plugin caches. Keep project fixes in the project, reusable agent setup in its source repo, and personal or machine-specific details in their private configuration.

3. Choose the first suitable mechanism in the preference order below. Explain any skipped option that would otherwise fit the finding. Apply the smallest change that addresses the demonstrated failure within the current authorization. A retrospective finding does not grant new permissions. If a change needs a user decision, prepare the concrete change for review and record what remains pending.

4. Verify the behavior of executable fixes. Reproduce the original failure and show that the change now rejects or corrects it. Exercise a valid case too. For ordered workflows, cause a prerequisite to fail and verify that later actions do not run. Use isolated fixtures for destructive or external actions. For judgment or prose changes, assess the original case and state what remains dependent on the agent. Run the owning repo's required checks.

5. Remove or shorten prose that the verified mechanism replaces. Keep context that explains a decision or helps recover from a failure. Run the `unslop` skill on changed agent-facing prose. Use the Skill tool when available; otherwise read `../unslop/SKILL.md` relative to this folder.

6. Account for each finding as applied, already handled, uncertain, or pending a named decision or dependency. Report the changed source, verification result, and any remaining way to bypass the requirement. Persist unresolved work in the project's existing tracker or private setup notes, according to its instructions.

## Preference order

This orders implementation choices, not guarantees. A separate mandatory check may still be needed to protect the result.

When adding a check, also choose its trigger and the operation its failure blocks. An unused validation script leaves the finding unresolved.

| Prefer | Mechanism | Example |
|---|---|---|
| 1 | Eliminate the separate step by making it part of the operation. | Saving a record also updates its index within the same transaction. |
| 2 | Reject invalid states through types, schemas, constraints, or restricted interfaces. | A database constraint rejects duplicate identifiers. |
| 3 | Put the sequence in executable code. | One release command builds, tests, packages, and publishes, stopping on failure. |
| 4 | Express the rule as an automated check. | A linter rejects a banned API; a test checks required behavior. |
| 5 | Require passing checks at the boundary that accepts the result. | A protected merge requires CI; deployment accepts only the validated artifact. |
| 6 | Attach a hook to the relevant event. | Format after edits or validate before commits. |
| 7 | Put task-specific judgment in a skill. | A review procedure explains how to assess an interface tradeoff. |
| 8 | Keep a short instruction for remaining context or judgment. | Explain why a compatibility workaround exists. |

For code patterns, start with the repo's linter. For sequencing, start with a script or workflow runner. For access restrictions, use permissions at the service or filesystem boundary. For an occasional judgment call, a skill may be the first suitable choice. Avoid building a classifier to enforce a subjective preference when the extra cost and errors outweigh the benefit.

## Check the enforcement claim

A check running automatically does not mean it blocks an invalid result. Verify these properties before claiming a requirement cannot be skipped:

- Every route to the protected operation passes through the check. Inspect direct commands and alternative entry points.
- Failure stops the operation. A warning, an ignored exit code, or an unavailable checker that allows the operation through is advisory.
- Passing evidence belongs to the exact revision, inputs, and artifact being accepted. A later edit invalidates earlier evidence.
- The agent performing the operation cannot disable the gate or rewrite its evidence through the same permissions. A local hook in an agent-writable checkout provides a weaker guarantee than a separately controlled acceptance check.

State the actual boundary. Distinguish a formatter that corrects edits, a test that detects errors, and a gate that refuses publication. An acknowledgment file proves that a file was written; it does not prove that the agent reflected, reviewed, or understood the work.
