# Backlog: nathanmcnulty/azd-reference

> Generated from `docs/backlog.json`. Edit the JSON source and regenerate this file.
> Standard: [azd agent backlog standard](https://github.com/nathanmcnulty/azd-reference/blob/main/standards/agent-backlogs.md). This link is review guidance, not a runtime dependency.

- **Schema version:** 1.0.0
- **Repository:** nathanmcnulty/azd-reference
- **Source revision:** `d3da9b0bd0d2df50bf55f736fd5f8986b3751341`
- **Captured:** 2026-10-07
- **Items:** 10

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

## REF-009: Preserve numeric HTML entities in generated backlog text

- **Kind:** maintenance
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Escaping Markdown hash markers after HTML encoding corrupted apostrophes and encoded Unicode in generated review evidence.

**Scope:**

- tooling/Export-AzdBacklogMarkdown.ps1
- tests/Backlog.Tests.ps1
- Generated Auth Notifications and Sysmon backlog Markdown

**Acceptance:**

- Preserve HTML encoder-produced numeric entities while keeping literal Markdown and raw entity input inert.
- Apostrophes and Unicode round-trip correctly without activating links, images or HTML.
- Regenerate affected consumer views without changing canonical task JSON or runtime code.

**Validation:**

- Invoke-Pester ./tests/Backlog.Tests.ps1 -PassThru
- Invoke-ScriptAnalyzer -Path tooling/Export-AzdBacklogMarkdown.ps1
- Regenerate and check affected Markdown views; independently review their exact one-file diffs and unchanged JSON.

**Dependencies:**

- REF-003

**Components:**

- _none_

**Sources:**

- tooling/Export-AzdBacklogMarkdown.ps1
- tests/Backlog.Tests.ps1

**Evidence:**

- 2026-10-06 independent exact-source review passed base 06d22bcf, two-path tree 67b78e705b8764aaa662b9a7e5cf3ec96bb2f73c and patch SHA-256 a6b88ad073690f3405665d0c26f9e10958a3b6c0e699e016e07ce651e2deea6d. The literal hash escape now excludes numeric entities already produced by HtmlEncode.
- Focused regression passed 10/10 locally and independently; script analysis and diff checks passed. Tests cover apostrophes, Unicode, literal headings and raw entity text alongside existing hostile Markdown.
- Independent consumer review passed only docs/backlog.md changes&colon; one Auth Notifications entity and three Sysmon canary apostrophe entities. Canonical JSON and runtime source hashes are unchanged. Consumer publication results are recorded in docs/portfolio-execution.md.

**Review and authorization note:**

Review REF-009 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

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

## REF-010: Qualify Intune Remediations 0.1.6 as a source-only pilot

- **Kind:** maintenance
- **Priority:** P1
- **Status:** done
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

The reviewed Intune publication/readback component remained only on preserved branch e5265492 and in two immutable staged consumer locks, so canonical source and tests were unavailable from main.

**Scope:**

- components/powershell/intune-remediations
- tests/IntuneRemediations.Tests.ps1
- Exact validation compatibility for the reviewed 0.1.6 bytes
- Source-only pilot documentation

**Acceptance:**

- Import the nine reviewed component/test paths from e5265492a949f2e111d3dac88d043b4f63175d3a without changing their blobs or reusing version 0.1.6 for different content.
- Cross-check the AV and Firewall immutable locks and vendored hashes without changing consumer files or pins.
- Keep every inherited analyzer finding bound to the exact module hash and finding tuple; changed, missing or additional findings fail validation.
- Retain pilot status and make no tag, release, deployment, authentication, grant, assignment or endpoint acceptance claim.

**Validation:**

- Invoke-Pester ./tests/IntuneRemediations.Tests.ps1 -PassThru
- Run the complete registered validation workflow locally, including PowerShell analysis, full Pester, catalog build, component/version/drift checks and Bicep assertions.
- Compare the exact e5265492 component sources with the AV and Firewall locks and vendored files on staging main fd1e708f26e01d7ccfc2d1fb1eaa0a6e80c99799.
- Independently review the exact source and final integration packets before commit and publication.

**Dependencies:**

- REF-005

**Components:**

- intune-remediations

**Sources:**

- standards/component-lifecycle.md
- components/powershell/intune-remediations/README.md
- https&colon;//github.com/nathanmcnulty/azd-reference/commit/e5265492a949f2e111d3dac88d043b4f63175d3a
- https&colon;//github.com/nathanmcnulty/azd-work-in-progress/tree/fd1e708f26e01d7ccfc2d1fb1eaa0a6e80c99799/azd-defender-av-exclusions
- https&colon;//github.com/nathanmcnulty/azd-work-in-progress/tree/fd1e708f26e01d7ccfc2d1fb1eaa0a6e80c99799/azd-defender-firewall

**Evidence:**

- The nine imported source/test paths match preserved revision e5265492a949f2e111d3dac88d043b4f63175d3a at the Git blob level. Focused PowerShell parsing and IntuneRemediations.Tests.ps1 passed 32/32; the complete registered local validation passed 333 Pester tests, exact PowerShell analysis, 11 catalog tests/build, component/version and skeleton lock/drift/sync checks, and all registered Bicep builds and positive/negative assertions.
- AV and Firewall each pin intune-remediations 0.1.6 to e5265492 with six managed files. All 12 lock hashes match both the imported source and current vendored files on staging main fd1e708f26e01d7ccfc2d1fb1eaa0a6e80c99799; neither consumer lock nor vendored file changes in this packet.
- AV publication, assignment and readback succeeded but the later SYSTEM result was visibility-blocked and value-free. Firewall produced a bounded 8-of-250 report with 242 omitted and a LocalOnly full artifact. These results qualify the transport boundary only; they do not prove inventory completeness, policy delivery, migration or enforcement acceptance.

**Review and authorization note:**

Review REF-010 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## REF-005: Reconcile component candidates and permission-aware feature metadata

- **Kind:** maintenance
- **Priority:** P2
- **Status:** done
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Candidate and optional-feature permission metadata were preserved on a separate Reference branch. Reconcile the finished metadata/tooling into main while keeping unqualified host/runtime and Teams extraction behind their existing gates.

**Scope:**

- docs/component-candidates.md
- docs/permission-comparison.md
- standards/permission-requirements.md
- schemas/permission-requirements.schema.json
- schemas/permission-solutions.schema.json
- portfolio/permission-solutions.json
- tooling/Get-AzdPermissionComparison.ps1
- tests/PermissionComparison.Tests.ps1
- skeleton/azd-permissions.json
- examples/deployment-check/azd-permissions.json
- README.md

**Acceptance:**

- Use component manifests and consumer locks as evidence; document stable, pilot and candidate status separately.
- Candidate Teams personal-bot and managed-connector components remain proposals until two consumers show delivery/lifecycle convergence.
- Optional features record only actual incremental permissions and known gaps; metadata never grants scopes or roles.

**Validation:**

- Invoke-Pester ./tests/PermissionComparison.Tests.ps1,./tests/Backlog.Tests.ps1 -PassThru
- Invoke-ScriptAnalyzer -Path tooling/Get-AzdPermissionComparison.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
- Validate template manifests against schemas/permission-requirements.schema.json; inspect local default and explicitly selected feature comparisons without granting permissions.
- Run the registered Reference validation workflow, aggregate backlog schema/dependency checks and generated-view checks.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- docs/component-candidates.md
- portfolio/consumers.json
- https&colon;//github.com/nathanmcnulty/azd-reference/blob/8d33a9ccaf0e0298ccd112f82a63820999814b9b/standards/permission-requirements.md
- standards/permission-requirements.md
- tooling/Get-AzdPermissionComparison.ps1
- https&colon;//github.com/nathanmcnulty/azd-reference/commit/e5265492a949f2e111d3dac88d043b4f63175d3a

**Evidence:**

- Pre-follow-through baseline&colon; Component candidate versions and four consumer upgrade decisions reconciled under REF-006. Permission-aware optional-feature metadata and additional extraction qualification remain proposed; this broader record is not complete.
- Pre-follow-through baseline&colon; Current-main reconciliation&colon; permission tracking is separately owned branch work, not part of this backlog/tooling integration; its historical source is linked explicitly.
- 2026-10-06 narrow metadata convergence reconciles nine finished schema/standard/registry/tool/test/template/example paths from immutable branch e5265492a949f2e111d3dac88d043b4f63175d3a, with a current README guide link and four-newer-runner clarification. No security host/runtime or Intune component source, registration or release was imported. Current main manifests separately identify one stable, six pilot and one candidate component, with unchanged immutable consumer pins.
- Focused permission comparison and backlog regressions passed 19/19; permission tool script analysis and both template metadata schema checks passed. Local read-only comparisons of ASR with AV/Firewall yielded zero default runtime requirements and six explicitly selected optional runtime/discovery requirements, with all three inventories still partial and comparisonComplete=false. No authentication, tenant reads or grants ran from this tool. Exact tuples retain principal/phase/feature evidence; missing coverage never becomes a permission-free or least-privilege claim. Teams transport extraction and shared hosting remain evidence-gated proposals.
- Independent review required two bounded corrections before final acceptance&colon; both schemas and the contained-path guard reject colon-bearing NTFS alternate data stream paths; saved comparison JSON records enabled/excluded features and optional-union selection. Focused 19/19 regression checks cover rejected stream paths and reproducible feature selections. Documentation accurately describes registered local files, without claiming Git tracking. These corrections are separately reviewed with the final exact packet.

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

Host/runtime components are preserved in branch revision e5265492a949f2e111d3dac88d043b4f63175d3a. The finished metadata packet excludes their 29 component/test paths; local candidate manifests do not establish canonical qualification, published immutable adoption or lifecycle proof.

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
- 2026-10-07 follow-through&colon; preserved revision e5265492a949f2e111d3dac88d043b4f63175d3a remains separate. Only permission metadata/tooling and starter manifests converge under REF-005; host/runtime/Intune component extraction requires its own exact-source review and consumer/lifecycle validation. No component registration or release is inferred.

**Review and authorization note:**

Review REF-007 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.
