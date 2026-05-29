---
issue: github.com/cracklings3d/common-code#135
title: Track canonical issue-plan template in repository
status: draft
plan_status: proposed
review_status: pending
source: issue
owner: cracklings3d
created_at: 2026-05-29
updated_at: 2026-05-29
approved_by: null
approved_at: null
review_artifact: null
related_branch: issue-135-track-canonical-issue-plan-template-in-repository
related_pr: null
replaces: null
supersedes: null
change_scope:
  files:
    - docs/issue-plans/TEMPLATE.md
    - docs/issue-plans/issue-135.md
  directories:
    - docs/issue-plans/
  modules: []
  artifacts:
    - tracked repository template artifact at docs/issue-plans/TEMPLATE.md
    - authoritative issue-135 tracked plan artifact at docs/issue-plans/issue-135.md on branch issue-135-track-canonical-issue-plan-template-in-repository
---

# Summary

This issue adds `docs/issue-plans/TEMPLATE.md` to the repository by tracking the bootstrap source `E:\ai-infrastructure\common-code\docs\issue-plans\TEMPLATE.md` so fresh worktrees and branches created from the default branch contain it without manual setup. `C:\Users\The_u\AppData\Local\Temp\opencode\worktrees\common-code\issue-135-track-canonical-issue-plan-template-in-repository\docs\issue-plans\issue-135.md` is the authoritative tracked plan artifact that governs implementation and review for issue #135 on this issue branch/worktree until merge.

# Problem

Fresh worktrees provisioned from the default branch do not contain `docs/issue-plans/TEMPLATE.md`, so canonical tracked plan creation and review can fail unless the file is installed manually. This blocks a repo-level workflow prerequisite and affects other issues only as downstream beneficiaries, not as part of this issue's implementation scope.

# Acceptance Criteria

- `docs/issue-plans/TEMPLATE.md` is committed and tracked in the repository with content copied unchanged from `E:\ai-infrastructure\common-code\docs\issue-plans\TEMPLATE.md`.
- Fresh worktrees and branches created from the default branch contain `docs/issue-plans/TEMPLATE.md` without manual setup after this issue is merged.
- Canonical tracked plan review can rely on the template being present in fresh worktrees.
- The implementation does not broaden the template contents.
- The implementation does not add automation or expand the workflow beyond tracking the template file.

# In Scope

- Add `docs/issue-plans/TEMPLATE.md` to this branch by copying `E:\ai-infrastructure\common-code\docs\issue-plans\TEMPLATE.md` unchanged.
- Create and maintain the canonical tracked plan for this issue at `docs/issue-plans/issue-135.md`, which is the authoritative plan artifact for implementation and review of issue #135 on this issue branch/worktree until merge.
- Verify the tracked template is the file intended to become available from the default branch through normal PR and merge flow.

# Out Of Scope

- Redesigning or broadening the template contents.
- Adding automation, bootstrap scripts, or workflow expansion.
- Pulling unrelated planning issues such as #118, #119, #122, #131, or #133 into this issue's change scope.

# Constraints

- Keep the change surface limited to `docs/issue-plans/TEMPLATE.md` and `docs/issue-plans/issue-135.md`, plus only minimal validation evidence if directly required for this issue.
- If bootstrapping is required, copy the template verbatim from `E:\ai-infrastructure\common-code\docs\issue-plans\TEMPLATE.md`.
- `C:\Users\The_u\AppData\Local\Temp\opencode\worktrees\common-code\issue-135-track-canonical-issue-plan-template-in-repository\docs\issue-plans\issue-135.md` is the authoritative tracked plan artifact governing implementation and review for issue #135 on this issue branch/worktree until merge.
- Do not modify the GitHub issue text as part of this stage.
- Do not implement automation, production code, or unrelated workflow changes.

# Proposed Approach

Bootstrap `docs/issue-plans/TEMPLATE.md` into this worktree by copying `E:\ai-infrastructure\common-code\docs\issue-plans\TEMPLATE.md` exactly, since this issue owns tracking that file. Maintain `C:\Users\The_u\AppData\Local\Temp\opencode\worktrees\common-code\issue-135-track-canonical-issue-plan-template-in-repository\docs\issue-plans\issue-135.md` as the authoritative tracked plan artifact governing implementation and review for issue #135 on this issue branch/worktree until merge. The plan directs implementation to add the tracked template file on this branch and rely on the normal PR and merge path to make the template available from the default branch for future worktrees.

# Impacted Areas

- `docs/issue-plans/TEMPLATE.md`
- `docs/issue-plans/issue-135.md`
- Fresh worktree and branch setup from the default branch after merge

# Validation Plan

- Confirm `docs/issue-plans/TEMPLATE.md` exists in the branch and matches `E:\ai-infrastructure\common-code\docs\issue-plans\TEMPLATE.md` exactly.
- Confirm `docs/issue-plans/issue-135.md` remains the authoritative tracked plan artifact governing implementation and review for issue #135 on this issue branch/worktree until merge.
- Confirm the planned implementation scope is limited to the tracked template file and this issue plan artifact.
- After implementation is merged to the default branch, create a fresh worktree or branch from the default branch and verify `docs/issue-plans/TEMPLATE.md` is present without manual setup.

# Risks

- The template could be copied with unintended content changes; mitigate by copying `E:\ai-infrastructure\common-code\docs\issue-plans\TEMPLATE.md` verbatim.
- Validation of default-branch availability cannot be fully completed until normal PR and merge flow finishes; mitigate by making post-merge fresh-worktree verification explicit.

# Open Questions

- None.

# Approval Notes

Issue #135 is a repo-level workflow prerequisite only. `docs/issue-plans/issue-135.md` in this issue branch/worktree is the authoritative plan artifact governing implementation and review for #135 until merge. Issues #118, #119, #122, #131, and #133 may benefit once the template is tracked on the default branch, but they are not part of this plan's implementation scope.
