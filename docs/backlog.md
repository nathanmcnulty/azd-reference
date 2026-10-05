# Backlog: nathanmcnulty/azd-reference

> Generated from `docs/backlog.json`. Edit the JSON source and regenerate this file.
> Standard: [azd agent backlog standard](https://github.com/nathanmcnulty/azd-reference/blob/main/standards/agent-backlogs.md). This link is review guidance, not a runtime dependency.

- **Schema version:** 1.0.0
- **Repository:** nathanmcnulty/azd-reference
- **Source revision:** `cd5d64ee37aa58553074966342dc553decfa31c8`
- **Captured:** 2026-10-04
- **Items:** 8

## REF-001: Reconcile this backlog with current source and active work

- **Kind:** discovery
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Plans and implementation evidence are spread across files; the captured source can change while other tasks work.

**Scope:**

- docs/backlog.json
- docs/backlog.md
- Existing roadmap, execution status, open issues and pull requests &lpar;read-only&rpar;

**Acceptance:**

- Classify each candidate as implemented, still open, superseded or awaiting evidence; retain source links and reasons.
- Inspect dirty state, remotes, worktrees and local environment presence without reading secrets; avoid duplicate work with active owners.
- Resolve the actual offline validation commands and record exact current default-branch/working-tree provenance; do not copy historical live passes to newer code.

**Validation:**

- git status --short
- git remote -v
- git worktree list --porcelain
- Read the applicable instructions and validation workflow; read gh issue list and gh pr list for the named repository using nathanmcnulty. Do not create or modify issues/PRs.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- README.md

**Evidence:**

- 2026-10-04 reconciliation against current main 54a29a590c8b015f5becf7457407128e1b413835&colon; read-only issue/PR inventory found issues &num;2/&num;3/&num;4/&num;65 closed and no open PRs. REF-003/006/008 retain bounded completed evidence; REF-002 CI pilot, REF-004 Flex qualification, REF-005 permission/extraction metadata and REF-007 separately owned security components remain proposed.
- Inspected status, remotes, worktrees and environment-directory presence without reading secrets. Preserved active permission/component owner branches and all current-main governance/catalog changes; selected only 17 owned backlog/registry paths plus fixture-local signing guards in PortfolioStatus and PortfolioUpdate &lpar;19 paths total&rpar;.
- Resolved current .github/workflows/validate.yml commands. Syntax/PSScriptAnalyzer, component-version and skeleton drift/WhatIf, catalog 11 tests/build, Bicep compiled positive/negative assertions, 30-root/202-record backlog validation and generated Markdown check passed locally. Historical live passes remain bound to their original runtime files; no new deployment or release is claimed.

**Review and authorization note:**

Review REF-001 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## REF-008: Make disposable Git test fixtures independent of interactive signing settings

- **Kind:** maintenance
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

PR &num;66 closes issue &num;65 and isolates ComponentSync fixtures, but PortfolioStatus fixtures still inherit commit and tag signing settings. Complete that bounded fixture gap without changing host signing configuration. Full current-main suite additionally exposed the same inherited signed-tag failure in PortfolioUpdate fixtures.

**Scope:**

- tests/PortfolioStatus.Tests.ps1
- tests/PortfolioUpdate.Tests.ps1
- docs/backlog.json
- docs/backlog.md
- BACKLOG.md

**Acceptance:**

- Disable commit and tag signing only in disposable PortfolioStatus and PortfolioUpdate fixture repositories; preserve the merged ComponentSync fix and host configuration.
- The affected suites pass with inherited global signing enabled and an unusable signing key.
- Independent review confirms the exact source diff and current-main provenance before commit and push.

**Validation:**

- Run the affected PortfolioStatus/PortfolioUpdate suites with temporary GIT&lowbar;CONFIG&lowbar;GLOBAL enabling commit.gpgsign and tag.gpgsign and an unavailable key; restore the process environment afterward.
- Run PSScriptAnalyzer on the changed test file and git diff --check.
- Validate the full canonical backlog set and check the generated Markdown.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- https&colon;//github.com/nathanmcnulty/azd-reference/issues/65

**Evidence:**

- Fresh GitHub read&colon; issue &num;65 closed and PR &num;66 merged at 54a29a590c8b015f5becf7457407128e1b413835; its only source change is tests/ComponentSync.Tests.ps1. PortfolioStatus fixtures at that revision still inherit signing.
- Independent source review passed the exact eight-line fixture-local change at SHA-256 2f05eacd90a4447128ca40804422f2aae45a3a2c3608f6b85ca3233ac7f4034d, based on current main 54a29a590c8b015f5becf7457407128e1b413835.
- PortfolioStatus focused regression&colon; 12 passed, 0 failed in 214.14 seconds with a temporary global configuration enabling commit and tag signing and an unavailable signer/key. Process environment was restored and the temporary file removed; host configuration was not edited.
- PSScriptAnalyzer matches the two pre-existing Pester variable-scope warnings exactly, with zero new findings; git diff --check passed. Reviewed source integrated after canonical baseline parity check; preservation branch codex/portfolio-fixtures-backlog-20261003.
- 2026-10-04 current-main full suite&colon; 287 passed and five PortfolioUpdate cases failed because inherited tag signing required an editor and prevented disposable fixture tag creation. Added the same fixture-local signing guard to its two repositories; no host signing settings or product code changed.
- PortfolioUpdate signing regression&colon; 17/17 passed in 85.83 seconds under temporary global commit/tag signing enabled with an unavailable SSH key. The process environment was restored and the temporary configuration removed.
- Final PortfolioUpdate guard explicitly uses git config --local and checks each native exit code. Hostile-signing regression rerun&colon; 17/17 passed in 87.10 seconds.

**Review and authorization note:**

Review REF-008 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## REF-002: Pilot the shared backlog contract in repository validation

- **Kind:** maintenance
- **Priority:** P1
- **Status:** done
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Backlog files need structural and dependency checks before agents can reliably select work.

**Scope:**

- standards/agent-backlogs.md
- schemas/backlog.schema.json
- tooling/Test-AzdBacklog.ps1
- tooling/Export-AzdBacklogMarkdown.ps1
- .github/workflows/validate.yml

**Acceptance:**

- Schema rejects missing acceptance, duplicate IDs, invalid states and unknown authorization classes.
- Semantic checks reject local/cross-repository cycles, unresolved dependency references, ready tasks with unmet dependencies, done without evidence, and claims without ownership.
- Markdown freshness check runs locally and can be added to normal CI after review; no required-check or catalog enforcement change.

**Validation:**

- Use the offline commands in the registered validation workflow; record the exact commands, revision and results before implementation is complete.
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- README.md
- .github/workflows/validate.yml

**Evidence:**

- Selected for this local reconciliation under the maintainer instruction to finish work not requiring judgment. The existing schema/semantic tools and ten regression tests enforce the bounded task contract and dependency/evidence/ownership checks.
- Added an ordinary step to the existing Windows/Linux validation job&colon; Test-AzdBacklog.ps1 and Export-AzdBacklogMarkdown.ps1 -Check. Both commands pass locally against the current repository; this adds no required check, catalog enforcement, runtime dependency, deployment or tenant action. Hosted validation is verified through the PR before main integration.

**Review and authorization note:**

Review REF-002 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## REF-003: Provide a read-only portfolio backlog report and local wave selector

- **Kind:** feature
- **Priority:** P1
- **Status:** done
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

The maintainer needs one aggregate view without maintaining a second copy of every task.

**Scope:**

- tooling/Get-AzdBacklogStatus.ps1
- tests/Backlog.Tests.ps1
- docs/portfolio-backlog.md

**Acceptance:**

- Aggregate declared repository-local backlogs into ordered rows by priority, wave, status, authorization and component task references; keep owning JSON as the only task database.
- ReadyOnly returns only ready/local-only tasks after validation of the full dependency set; PowerShell filtering selects waves without claims, scheduling or issue writes.
- Missing input paths, unresolved IDs, duplicate identities and invalid dependency states fail validation; source freshness is reviewed by the executing agent from recorded snapshot provenance.

**Validation:**

- Invoke-Pester ./tests/Backlog.Tests.ps1 -CI
- Pass the complete declared backlog paths to tooling/Test-AzdBacklog.ps1 and tooling/Get-AzdBacklogStatus.ps1; compare aggregate and ReadyOnly counts with canonical JSON.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- tooling/Get-AzdBacklogStatus.ps1
- tests/Backlog.Tests.ps1
- docs/portfolio-backlog.md

**Evidence:**

- 2026-10-03 local validation of the new tooling&colon; 31 declared backlog roots resolved; initial 175-row aggregate matched all canonical records; ReadyOnly returned 35 ready/local-only reconciliation tasks.
- Invoke-Pester tests/Backlog.Tests.ps1&colon; 10 passed, 0 failed. Full PSScriptAnalyzer across the three new tools&colon; no findings. No new hosted-CI run or release is claimed.

**Review and authorization note:**

Review REF-003 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## REF-004: Qualify identity-only Flex host storage before widening adoption

- **Kind:** discovery
- **Priority:** P1
- **Status:** proposed
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

The Flex host is a pilot; its existing storage credential boundary should be compared with identity-only consumers before reuse.

**Scope:**

- components/bicep/flex-scheduled-poller-host/
- tests/
- docs/component-candidates.md

**Acceptance:**

- Document exact host/deployment/checkpoint identity and RBAC boundaries; preserve portable solution-owned state and delivery.
- Pilot changes with at least two real consumer shapes; no runtime fetches or forced Log Analytics.
- Publish a reviewed immutable version only under separate release authorization; drifted consumer files are never overwritten.

**Validation:**

- Use the offline commands in the registered validation workflow; record the exact commands, revision and results before implementation is complete.
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- flex-scheduled-poller-host

**Sources:**

- docs/component-candidates.md
- components/bicep/flex-scheduled-poller-host/component.json

**Evidence:**

- _none_

**Review and authorization note:**

Review REF-004 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## REF-006: Register existing Auth Notifications adoption and compare validation upgrades

- **Kind:** maintenance
- **Priority:** P1
- **Status:** done
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Auth Notifications has a component lock but no central consumer entry; four consumers remain on deployment-validation 1.0.0 while the tracked manifest is 1.1.1.

**Scope:**

- portfolio/consumers.json
- docs/component-candidates.md
- Four consumer upgrade plans only
- nathanmcnulty/azd-auth-notifications/scripts/Test-Repository.ps1

**Acceptance:**

- Register Auth Notifications as existing adoption with its actual immutable pins and validation entry point.
- Prepare independent upgrade decisions for Auth Notifications, Device Notifications, Emergency Access and PIM; do not overwrite active vendor drift.
- Update stale candidate-document versions from manifest/lock evidence; keep pilot enforcement and deployments independent.

**Validation:**

- Invoke-Pester ./tests -CI; for disposable fixtures only, disable inherited Git commit/tag signing process-locally as recorded in the execution evidence.
- Invoke-Pester ./tests/Schema.Tests.ps1, ./tests/PortfolioStatus.Tests.ps1
- Run the static, catalog, component, skeleton and Bicep commands recorded in .github/workflows/validate.yml; the packet used local Bicep 0.46.1, while hosted CI pins 0.42.1.
- From Auth Notifications root&colon; pwsh -File ./scripts/Test-Repository.ps1

**Dependencies:**

- _none_

**Components:**

- deployment-validation
- notification-contracts

**Sources:**

- portfolio/consumers.json
- docs/component-candidates.md

**Evidence:**

- Selected for local implementation by maintainer instruction 2026-10-03&colon; coordinate backlog local-first with independent review and lab validation as needed; publication, enforcement and external delivery remain outside this code packet.
- Independently reviewed registry and consumer wrapper integrated into canonical checkouts 2026-10-03 after file/base drift checks. Independent wrapper execution&colon; 28/28 tests, build/typecheck, Bicep, PSSA; focused Schema/PortfolioStatus&colon; 47/47. Full clean reference suite still running; status remains in-progress until its result is captured.
- Final reference validation&colon; 282/282 Pester, syntax/PSScriptAnalyzer, catalog audit and 11/11 tests/build, component/skeleton drift and sync WhatIf, Bicep assertions, and diff check passed. Disposable Git fixture signing was disabled process-locally for known issue &num;65; product code unchanged. Independent review passed the exact reference diff 7d8ba38619aa85d454d8f14c39de21925b71e19e335b749ebfc336de9c27f256 and consumer wrapper SHA256 900d15e2760ed537c475c4a9d38ab3ecbefbf2e3e45487fd00690afdb9ad802b. Changes integrated locally; no release or merge is claimed.

**Review and authorization note:**

Review REF-006 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## REF-005: Reconcile component candidates and permission-aware feature metadata

- **Kind:** maintenance
- **Priority:** P2
- **Status:** proposed
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Candidate inventory contains older Maester hook versions and teams lifecycle extraction remains evidence-gated.

**Scope:**

- docs/component-candidates.md
- portfolio/consumers.json
- https&colon;//github.com/nathanmcnulty/azd-reference/blob/8d33a9ccaf0e0298ccd112f82a63820999814b9b/standards/permission-requirements.md

**Acceptance:**

- Use component manifests and consumer locks as evidence; document stable, pilot and candidate status separately.
- Candidate Teams personal-bot and managed-connector components remain proposals until two consumers show delivery/lifecycle convergence.
- Optional features record only actual incremental permissions and known gaps; metadata never grants scopes or roles.

**Validation:**

- Use the offline commands in the registered validation workflow; record the exact commands, revision and results before implementation is complete.
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- docs/component-candidates.md
- portfolio/consumers.json
- https&colon;//github.com/nathanmcnulty/azd-reference/blob/8d33a9ccaf0e0298ccd112f82a63820999814b9b/standards/permission-requirements.md

**Evidence:**

- Component candidate versions and four consumer upgrade decisions reconciled under REF-006. Permission-aware optional-feature metadata and additional extraction qualification remain proposed; this broader record is not complete.
- Current-main reconciliation&colon; permission tracking is separately owned branch work, not part of this backlog/tooling integration; its historical source is linked explicitly.

**Review and authorization note:**

Review REF-005 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## REF-007: Review proposed security-automation host/runtime extraction boundaries

- **Kind:** discovery
- **Priority:** P2
- **Status:** proposed
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Host/runtime components were newly committed in active reference branch revision 9ed4c575cc057a4a96c05ce91c7dd9b7694da7b7 during this review, and further changes remain active. Local pilot manifests do not establish published immutable adoption or lifecycle proof.

**Scope:**

- Proposed components/security-automation-host and security-automation-runtime
- docs/
- tests/

**Acceptance:**

- Coordinate with the active owner and inspect an exact finished diff; preserve their unrelated source and tests.
- Separate host-neutral engine logic from Function/Automation/Logic App adapters; require two compatible consumer examples before shared runtime extraction.
- Document identity, optional permission switches, state, failure and teardown isolation; no registration, release or adoption from self-labelled pilot status.

**Validation:**

- Use the offline commands in the registered validation workflow; record the exact commands, revision and results before implementation is complete.
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- security-automation-host
- security-automation-runtime

**Sources:**

- docs/component-candidates.md
- standards/component-lifecycle.md
- https&colon;//github.com/nathanmcnulty/azd-reference/blob/9ed4c575cc057a4a96c05ce91c7dd9b7694da7b7/components/bicep/security-automation-host/component.json
- https&colon;//github.com/nathanmcnulty/azd-reference/blob/9ed4c575cc057a4a96c05ce91c7dd9b7694da7b7/components/powershell/security-automation-runtime/component.json

**Evidence:**

- Current main 54a29a590c8b015f5becf7457407128e1b413835 contains neither proposed security component. Historical branch manifests are evidence of separate owner work; no implementation or adoption is imported by this reconciliation.

**Review and authorization note:**

Review REF-007 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.
