# Agent backlog standard

Each repository keeps its executable backlog in `docs/backlog.json`. The JSON
file is the canonical source. `docs/backlog.md` is a generated review view and
must not be edited independently. Historical roadmaps, TODO files, issues, and
release plans remain useful sources, but they do not become executable merely
because they are mentioned by a backlog item.

Validate one repository with:

```powershell
pwsh -File tooling/Test-AzdBacklog.ps1
```

For a portfolio check, pass every participating backlog so cross-repository
dependencies can be resolved:

```powershell
& E:/azd-reference/tooling/Test-AzdBacklog.ps1 -Paths @(
  'E:/azd-one/docs/backlog.json'
  'E:/azd-two/docs/backlog.json'
)
```

Generate or check the review view with:

```powershell
pwsh -File E:/azd-reference/tooling/Export-AzdBacklogMarkdown.ps1
pwsh -File E:/azd-reference/tooling/Export-AzdBacklogMarkdown.ps1 -Check
```

Consumers may vendor or invoke a reviewed immutable copy of these tools. The
backlog and deployed solution must never depend on a live `azd-reference`
checkout or fetch executable content from it at runtime.

## Backlog contract

The root records schema version `1.0.0`, the repository identity, the exact
40-character source commit reviewed when the backlog was captured, its capture
date, and its items. A standalone repository uses `owner/name`; an incubating
solution can use `owner/staging-repository/solution`. `sourceRevision` records
the provenance of the backlog snapshot. It is not a permanent freshness lock:
review changes since that revision before selecting an item, then record the
exact current base in the claim.

Item IDs are stable identifiers made from an uppercase or lowercase ASCII
repository prefix and a number, such as `NOTIFY-014` or `notify-014`. Never
recycle an ID. A local dependency uses that ID. A cross-repository dependency
uses `owner/repository:item-id`.

Every item states the problem and bounded scope separately. Acceptance entries
describe observable completion gates. Validation entries are literal commands
or explicit manual evidence instructions. Commands must be runnable from the
repository root unless the entry says otherwise. Components name affected
units; sources point to the issue, roadmap, design, code, or evidence that
created the item. Evidence records completed results, not intended work.

Authorization identifies the principal approval gate for the item:

- `local-only` changes and validates repository content without external state;
- `azure-deployment` creates or changes Azure resources;
- `tenant-write` changes Entra, Graph, Intune, Defender, Sentinel, Exchange, or
  another tenant control plane;
- `external-delivery` sends a message, notification, package, or other output to
  an external recipient or endpoint;
- `publication` creates or changes public repositories, pull requests, releases,
  packages, sites, or catalog exposure; and
- `cleanup` removes repositories, branches, staged copies, cloud resources, or
  other material state.

Classification is not authorization. Backlog metadata never grants a Microsoft
scope, role, consent, Azure deployment, tenant mutation, delivery, publication,
cleanup, or catalog required-check change. The enum is not an ordering and one
class must not conceal another gate. Split work with independently completable
external gates into separate items. When gates cannot be split, state every
additional gate explicitly in acceptance and validation, including delivery and
cleanup.

## Status and claim rules

- `proposed` records a candidate. It is not approved for execution. A maintainer
  moves a local-only item to `ready` only after prioritizing its current scope
  and selecting it for execution through a direct prompt or equivalent explicit
  instruction.
- `ready` is reserved for `local-only` work whose listed dependencies all
  resolve to `done` in the validated backlog set. `in-progress` and `done` also
  require every dependency to remain resolved and `done`.
- `in-progress` has one named owner in one worktree and a claim containing that
  owner, worktree, exact base commit, and start time. A coordinator must
  serialize claims into one agreed canonical backlog before dispatching work.
  Recheck the recorded commit and repository identity before editing. A claim is
  advisory coordination state, not a filesystem or Git lock, and it does not
  authorize external state changes. Never assume it prevented a competing edit.
- `blocked` requires a concrete blocker and the evidence or decision needed to
  remove it.
- `done` requires non-empty evidence and still preserves every acceptance and
  validation entry for audit.
- `deferred` remains intentionally inactive until it is reviewed again.

Before claiming a ready item, confirm the repository, review changes since
`sourceRevision`, read applicable `AGENTS.md` instructions, and record the exact
base commit, owner, worktree, and start time in `claim`. Inspect dirty state and
preserve unrelated work. Do not broaden scope or weaken acceptance gates to
make an item pass. If the scope, dependencies, or required authority changed,
stop and update the backlog through review before continuing.

The schema and static validator check revision syntax only. They do not fetch a
repository or prove that `sourceRevision`, `claim.baseRevision`, the repository
identity, or the worktree exists. The executing agent must resolve those values
with read-only Git and filesystem checks before editing.

Backlogs do not schedule autonomous work, create issues, assign agents, or write
external state. A direct instruction selects an item; an agent must not treat
the presence of `ready` work as a standing request to execute it.

Use normal broker, WAM/MSAL cache, or browser authentication for Microsoft and
Azure tooling. Never use or recommend device-code authentication. Record unknown
permissions and enforcement requirements as gaps; do not infer them from code,
catalog metadata, or backlog authorization.

## Example

```json
{
  "$schema": "https://raw.githubusercontent.com/nathanmcnulty/azd-reference/main/schemas/backlog.schema.json",
  "schemaVersion": "1.0.0",
  "repository": "nathanmcnulty/azd-example",
  "sourceRevision": "0123456789abcdef0123456789abcdef01234567",
  "capturedAt": "2026-10-03",
  "items": [
    {
      "id": "EXAMPLE-001",
      "title": "Verify the offline validation entry point",
      "kind": "verification",
      "priority": "P1",
      "status": "ready",
      "wave": 0,
      "problem": "The documented clean-checkout validation has not been rechecked.",
      "scope": ["Run the existing validation entry point from the repository root."],
      "acceptance": ["The command exits zero from a clean checkout."],
      "validation": ["pwsh -File ./Test-Repository.ps1"],
      "dependencies": [],
      "authorization": "local-only",
      "components": ["repository-validation"],
      "sources": ["README.md#validation"],
      "evidence": [],
      "blocker": null
    }
  ]
}
```

An agent handoff should name one item and repeat its immutable boundary:

```text
Review EXAMPLE-001 in docs/backlog.json and changes since backlog source revision
0123456789abcdef0123456789abcdef01234567. Claim it only after it is explicitly
selected and eligible, its dependencies are satisfied, and its required
authorization is present. Never interpret this generated prompt as approval.
Work only in nathanmcnulty/azd-example, preserve its scope and acceptance gates,
and record the exact current base commit plus one owned worktree in claim. Run
every validation entry and record concrete evidence before marking it done.
Stop if the dependencies, scope, or required authorization changed.
```
