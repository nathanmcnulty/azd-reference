# Maester ownership-aware lifecycle

Hooks **3.0.0** follows the reviewed 2.1.0 consent/session contract. It is a breaking cleanup migration: environment IDs, display names and matching tags no longer authorize deleting external objects. The four standalone consumers must adopt the canonical files together with their actual preprovision, setup, predown and postdown callers.

## What `azd down` owns

The supported initial round trip uses a **fresh, dedicated resource group**, no sharing and no concurrent provisioning from other processes or machines. A preprovision hook records intent before creating an absent selected group, accepts ownership only from the exact ARM **201 Created** response, and checkpoints it immediately. A 200 response, timeout, malformed response or failed checkpoint is not ownership proof. Existing groups are never silently adopted.

Postprovision binds the exact resource and lock IDs declared by the reviewed Bicep source before optional access setup starts. Repeated same-source completion retains the proven inventory and prior lock history. ARM-listed foreign resources and unowned locks block down. The ownership marker rejects a different group incarnation; the marker/tag alone does not prove creation.

Deleting the dedicated group deletes its accounts, child resources and contents, including stored reports, packages and other data. ARM's resource-group listing does **not** enumerate every provider child or data-plane item. Do not share these accounts or add unrelated workloads. The code does not claim an exhaustive provider-content inventory or a distributed transaction.

## Durable external ownership

The selected environment retains two local, ignored files under `.azure/<environment>/`:

- `maester-infrastructure-ownership.json`: exact infrastructure creation proof, reviewed source/inventory, lock checkpoints and whether external setup started.
- `maester-setup-ownership.json`: exact tenant/subscription/environment/solution bindings, protected setup-client identity and per-operation external ownership.

Keep these files for the full deployment lifecycle and recovery. They contain nonsecret identity/operation metadata, not tokens or credentials. Unsigned local files cannot prove authenticity against an attacker able to rewrite them; cleanup independently verifies live provider IDs, complete tuples and dependencies.

Setup holds one local lifecycle lock before fresh target revalidation and throughout its writes. Each write records pending intent first, then persists exact response IDs before another remote operation or readback. No-op setup retains earlier ownership. Unknown outcomes remain pending and block replay; matching names or later discovery cannot convert them into creation evidence. A missing external journal after the infrastructure marker says setup started blocks down.

New grants and federated credentials on an adopted parent have their own ownership. Deployment-owned external identities and objects must stay dedicated for their entire lifetime; do not repurpose, share or concurrently edit them. Configuration/dependency checks cover the reviewed fields (including web redirects, identifier URIs and sign-in audience), not every possible application property or downstream reference. They are not a guarantee that arbitrary later reuse will be discovered. Reusing an application, service connection, pipeline or repository does not make that parent deployment-owned. Shared changes requiring concurrency-safe restoration remain explicit unresolved records until a supported recovery flow exists. A later material update to an already recorded shared mutation/publication can require reconciliation; the journal does not silently rewrite earlier before/after history.

## Owned repository publication updates

Hooks 3.1.0 supports one narrow successor contract for a branch in a receipted,
deployment-owned Azure DevOps repository. Each new publication explicitly names
its terminal applied predecessor, binds the previous commit to that receipt, and
records the planned new commit before the remote push. Earlier receipts remain
immutable. A no-op retains the existing receipt; an unknown push outcome remains
pending and blocks further setup. Shared/adopted repositories and other mutation
types do not receive this successor behavior.

The chain must keep the same organization, project, repository, branch and owned
parent, with no forks, cycles, missing predecessors or rewritten commits. Cleanup
accepts only the terminal recorded commit for each live owned branch, so a rollback
to an older recorded commit or unrelated source change still blocks deletion.
This lets a host separately approve unrun pipeline preparation, exact-pipeline
authorization and later chosen schedule/file updates without losing teardown
evidence. It does not activate schedules or authorize runs by itself.

## Hook order and approval

1. **Predown** checks receipts, fresh ARM context and the dedicated group inventory. It previews external effects but does not delete apps, grants or Azure DevOps objects.
2. If deployment-owned delete locks exist, a **separate default-No confirmation or exact current unlock-plan hash** authorizes only those IDs. Foreign locks block. If azd's later infrastructure prompt is canceled, these explicitly approved locks remain removed; Azure resources and external authorization remain unchanged.
3. **Azd** presents its normal infrastructure-deletion confirmation. A generic `--force` is not approval of the hook's unlock or external-cleanup plans.
4. **Postdown** proves the exact bound resource group/runtime absent, loads the latest journal under its lifetime lock, and creates a fresh external cleanup plan. Directly invoking postdown while Azure remains is rejected.
5. External cleanup requires a fresh default-No confirmation or exact plan hash. Each owned child/assignment is verified, checkpointed as deleting, removed by exact ID and checked for absence before a terminal receipt. Only authoritative not-found counts; permission failures, timeouts, tuple changes, foreign dependencies and still-visible objects fail.

The postdown PowerShell process needs its own selected setup session. The exact delegated scope union is printed before any optional normal-browser login. Those scopes must already have separately approved administrator consent; stop on new consent or unexpected device-code prompts. The Process-context SDK shared authentication-record caveat from the consent documentation still applies. There is no Azure CLI Graph-token fallback and no runtime permission to grant itself access.

If Azure deletion succeeds but external cleanup fails or is declined, the hook returns failure and says external cleanup is incomplete. Receipts remain. Run `scripts/Run-AzdPostDown.ps1 -PlanOnly` with the explicit original environment/tenant/subscription to inspect the remaining plan, then approve that current plan using `-ApprovedPlanHash`, or use `-InteractiveConsent` in a fresh PowerShell process. Normal browser login, if needed, is separately explicit. Rechecking Azure absence is mandatory on every retry.

## Preserved and separately managed prerequisites

The administrator-created public setup client, its service principal/consent, and the selected access group are external prerequisites. This deployment does not create or own that client, and `azd down` does not delete it. A temporary validation bootstrap needs its own exact ownership receipt and separately approved cleanup using an independent administrator identity; never self-delete the client while using it.

Legacy/reused groups, old configuration-only grant lists, uncertain or malformed create responses and unsupported shared-object rollback require explicit recovery. A partial malformed response remains pending even when one identity fragment is known. Completed down retains its receipts; same-environment reprovision is intentionally blocked until a reviewed reset/recovery flow exists. Use a fresh named environment for the supported initial round trip. Their presence is reported as a blocker, never hidden by manual cleanup or a successful exit. Deleting an owned Azure DevOps build definition also deletes its associated builds, history and artifacts; that consequence is included in the exact cleanup plan. The provider does not support a revision-conditional DELETE, so a fresh revision read is a guard rather than an atomic concurrency guarantee. Reused ADO repository publication/history and shared endpoint-wide authorization need preservation-safe, independently reviewed restoration rather than repository deletion or branch reset.

## Qualification boundary

Offline tests must exercise real setup and actual predown/postdown entrypoints with provider-boundary fixtures, covering cancellation, no-op repeats, partial writes, missing receipts, stale approval, wrong bindings, protected identities, foreign dependencies, typed absence and safe retries. Static source assertions alone are insufficient.

Native acceptance remains separately approved: capture before inventories, run actual `azd up` and `azd down`, test cancellation/unlock semantics, then verify owned Azure/Graph/Exchange/ADO objects absent and preserved prerequisites present. No manual deletion may mask a lifecycle failure. Source tests, review and hosted CI do not establish that live result.
