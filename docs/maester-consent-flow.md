# Maester 2.3.0 setup and permission reconciliation

This source-only pilot changes `maester-azd-hooks` from 1.0.0 to **3.0.0** and
requires `graph-delegated-authentication` **1.1.0** beside it. Synchronize both
components from one reviewed immutable Reference revision. No release, tenant
consent, deployment, or existing-consumer adoption is implied by these sources.

## Keep setup and assessment identities separate

- The setup operator signs in with a tenant-owned, single-tenant public-client
  application and an explicitly selected administrator account. The client has no
  secret. Its delegated permissions authorize setup only, subject to the signed-in
  administrator's roles.
- Hosted assessments retain their managed identities or, for Azure DevOps, their
  explicitly selected tenant-owned federated application. Managed identity remains
  the grant command's default. The additional federated contract below requires
  exact identity and trust provenance; a generic application ID is insufficient.
  Both modes permit only the reviewed assessment/capability manifest. Runtime
  identities do not receive app-granting, directory-role-writing, or
  delegated-consent-management permissions.
- A human running an interactive assessment should use a separate assessment
  client with delegated assessment scopes, not the privileged setup client.

The canonical Graph request path no longer acquires tokens from Azure CLI, exposes
raw Graph access tokens, or replaces the global `Invoke-MgGraphRequest` command.
ARM and explicitly tenant-bound Exchange token helpers remain separate.

## One-time authorized administrator bootstrap

The new setup client cannot create or consent itself. An authorized administrator
must create it in the selected tenant, or use an already-authorized provisioning
process. This step is intentionally outside unattended `azd up`.

1. In Microsoft Entra App registrations, register a clearly named setup-only app
   for **Accounts in this organizational directory only**.
2. Add a **Mobile and desktop applications** public-client redirect of
   `http://localhost`. For Windows broker sign-in also add
   `ms-appx-web://Microsoft.AAD.BrokerPlugin/<client-id>`.
3. In the enterprise application, require assignment and assign only designated
   setup administrators/groups. Review the app's delegated scope union below and
   grant the necessary administrator consent explicitly. App registration and
   `requiredResourceAccess` declarations alone do not constitute consent.
4. Record the nonsecret identifiers in the selected azd environment:
   `MAESTER_SETUP_CLIENT_ID` and `MAESTER_SETUP_ACCOUNT` (administrator UPN), plus
   the already-required `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID`.

For the base Graph application-role assignment operation, the setup scope union
is `Application.Read.All`, `AppRoleAssignment.ReadWrite.All`, and
`Directory.Read.All` (organization/domain validation). Selecting Teams adds
`RoleManagement.ReadWrite.Directory`. Selecting the optional Easy Auth Web App
adds `Application.ReadWrite.All`, `DelegatedPermissionGrant.ReadWrite.All`, and
`Group.Read.All`. Exchange and Azure service authorization remain separate.

Review this union before establishing the setup client's consent. Scope expansion
on a later upgrade requires new explicit approval; there is no self-consent API
call, `.default` request, coordinator-requested device-code fallback, or automatic
broad scope retry. SDK-internal authentication behavior is qualified separately
below.
The operator also needs appropriate directory/workload roles. Granting Microsoft
Graph application permissions requires Privileged Role Administrator or Global
Administrator; consent scopes alone do not supply that role.

Microsoft's [custom delegated client guidance](https://learn.microsoft.com/en-us/powershell/microsoftgraph/authentication-commands?view=graph-powershell-1.0#use-delegated-access-with-a-custom-application-for-microsoft-graph-powershell)
and [application-role assignment permissions](https://learn.microsoft.com/en-us/graph/api/serviceprincipal-post-approleassignments?view=graph-rest-1.0)
are the bootstrap references. Do not enable extra authentication flows merely to
avoid a failed normal browser/broker login.

## One verified session for the selected setup union

Choose optional setup features first, then call `Get-MaesterSetupScopes` with
those choices. Initialize `Assert-GraphAccess` with that complete union, tenant,
client, and account. Maester explicitly requires `ContextScope Process`; an
inherited CurrentUser context is refused, so use a fresh `pwsh -NoProfile` process.
An exact Process context can be reused within that process. `-AllowInteractive`
permits one SDK login request when necessary;
`-AllowContextReplacement` is a separate explicit choice to replace an incompatible
inherited session. An exact matching context is reused only after a read-only
probe. A wrong tenant, cloud, client, account, authentication type or missing scope
fails closed. Setup additionally verifies the client belongs to this tenant and
has a single-tenant public-client registration.

Process scope selects in-memory token caching, but Graph 2.41 still has shared
on-disk authentication-record and internal fallback behavior. It is not a complete
cache-isolation guarantee. No live login is qualified by the mocked setup tests;
review the [SDK limitations](graph-authentication.md) before native sign-in and
stop if an unexpected device-code flow appears. The coordinator never requests
an alternate flow or performs a global disconnect/cache cleanup itself.

Use `Invoke-GraphRestRequest` for subsequent Graph operations. It verifies the
captured session again before each request and never reconnects at a write
boundary. Do not call the SDK directly from migrated setup code. No Graph access
is needed merely to collect wizard options in preprovision.

## Full/Minimal and separate write capabilities

The interactive wizard asks **Grant the permissions needed for the full
assessment? [Y/n]**. Yes selects the reviewed `Full` 2.3.0 inventory; No selects
`Minimal`. This selects desired coverage, not consent approval. Noninteractive
runs preserve an explicit profile and default to Minimal when none was supplied.
`Extended` remains the exact legacy profile and is never silently renamed Full.

`Mail.Send` is disabled by default and included only for explicitly configured
report delivery. `ReportSettings.ReadWrite.All` is a separately selected,
default-off tenant-setting capability. Neither belongs to Full. All permissions
must exist as enabled application roles in the selected tenant before the first
grant. Licensing, service configuration, unsupported app-only tests and optional
preview workloads can still limit coverage; never suppress tests to hide gaps.

## Review a versioned delta before writes

`Grant-MaesterGraphPermissions.ps1` is **plan-only by default**. It verifies the
selected runtime identity, completely enumerates existing assignments, resolves every
requested role, and returns a versioned plan. The plan includes tenant, principal,
resource/role tuples, Maester and manifest versions, manifest SHA-256, profile,
optional capability flags, desired grants, missing grants, and a deterministic
`planHash`. Tokens, secret values and certificate material are never included.
For federated targets, the plan includes nonsecret credential identifiers and
validity dates so existing alternative ways to authenticate are visible.

Review the exact delta and then invoke the same command with `-Apply` and
`-ApprovedPlanHash <reviewed-hash>`. The command rebuilds its plan from live state
before writing. A changed tenant, principal, manifest, selection, or missing set
invalidates the approval. `Confirm-MaesterConsentPlan` offers explicit interactive
review with a default-No prompt; unattended expansion requires a supplied exact
hash. A zero-delta rerun does not request consent or create duplicates.

Keep all optional workload-role, Azure RBAC and Easy Auth expansions in the
consumer's separately reviewed setup envelope. Do not treat a Graph application
plan as approval of those additional changes. Switching Full to Minimal preserves
existing grants; removal needs its own review. Plans display preserved Graph grants
and their optional-capability consequences even when current flags are false. An
existing report-setting write grant can still permit the assessment to change
tenant report privacy; existing Mail.Send alone does not configure or trigger
delivery. A partial failure is not success:
new assignments are read back as exact principal/resource/role tuples, and retry
plans reflect what actually succeeded.

Assignment readback does not prove a runtime identity's cached token has refreshed
or that the assessment can execute every selected test. Run the pinned 2.3.0
runtime and inspect its effective-access and assessment receipt separately.

## Explicit federated-application runtime targets

Hooks 2.1.0 adds `-TargetType FederatedApplication` for hosts such as Azure DevOps.
The default `ManagedIdentity` mode still rejects application principals and rejects
federation parameters, even if empty. The explicit application mode requires:

- `ExpectedApplicationId`: runtime application/client GUID.
- `ExpectedApplicationObjectId`: tenant-local application object GUID.
- `ExpectedFederatedCredentialIssuer` and `ExpectedFederatedCredentialSubject`:
  exact, case-sensitive values from the independently verified deployment endpoint.
- The existing `TenantId` and `PrincipalObjectId`: exact deployment tenant and
  runtime service-principal object GUID.

The helper verifies the service principal is type `Application`, has the expected
client ID and is owned by the selected tenant. It reads the exact application
object and requires matching IDs and `AzureADMyOrg`. It completely enumerates
federated identity credentials with bounded, same-collection HTTPS pagination,
rejects malformed or duplicate entries, and requires exactly one match for the
issuer, subject and single audience `api://AzureADTokenExchange`. The verified
setup client's ID is read from the captured session, never from a later mutable
environment variable. It cannot be used as the runtime target.

The plan binds the matched credential ID, complete preserved federation inventory,
and application/service-principal key/password credential metadata. Existing
alternative trusts or credentials can exercise any newly granted application
roles; approval therefore applies to the whole runtime identity, not just one
pipeline. These existing authentication methods are displayed and preserved.
Changing identity, trust, credential metadata or assignment state invalidates the
old plan hash. The helper does not create, modify or delete applications,
credentials, service connections or federation.

The host remains responsible for independently checking its endpoint's exact ID,
type, authentication scheme, tenant, subscription/resource scope and client ID.
A display name, an arbitrary caller-supplied issuer, or a Graph application lookup
alone does not establish deployment provenance. New identity or endpoint creation
must be covered by a separate, read-only-by-default bootstrap plan and explicit
approval. If trust identifiers become known only after creating an endpoint,
stop and request approval for the fresh exact trust plan before creating the FIC.
After bootstrap, build and approve a fresh access plan using resolved exact IDs;
never continue to runtime grants under a placeholder plan.

The read-only Graph validation uses the existing `Application.Read.All` delegated
scope; application or FIC bootstrap needs the separately declared
`Application.ReadWrite.All` scope before establishing the one setup session.
See Microsoft's [federated-credential list permissions](https://learn.microsoft.com/en-us/graph/api/application-list-federatedidentitycredentials?view=graph-rest-1.0)
and [service-principal ownership and type fields](https://learn.microsoft.com/en-us/graph/api/resources/serviceprincipal?view=graph-rest-1.0).

## Caller migration and rollout boundaries

- Add the coordinator lock entry and both new Maester managed files (the manifest
  and consent-plan module) through normal synchronization, not hand editing.
- Replace global-shadow-dependent calls with `Invoke-GraphRestRequest`; initialize
  the complete selected setup union once.
- Accept `Full`, preserve explicit `Extended`, and pass optional mail and tenant
  write capability flags separately.
- Change grant entrypoints to plan/review/apply. Do not infer approval from a saved
  profile, configured recipient, earlier release, or old consent hash.
- Preserve #111 target checks, exact subscription/tenant/managed identity guards,
  consumer preserve-access controls, and existing owned-resource receipts.

The initial adoption packet targets Automation and Container Apps. Function and
Azure DevOps require their own dependent adoption and regression review. Azure
DevOps adoption must opt into the 2.1.0 federated-application contract above and
retain its independent endpoint provenance checks. Retained `azd-maester` migration copies are a separate rollout;
the Maester source fork's newer development branch must not be downgraded.

## Ownership-aware lifecycle

Hooks 3.0.0 adds durable per-write ownership and safe down hooks. See [the lifecycle contract](maester-owned-lifecycle.md) for fresh resource-group proof, exact lock approval, postdown cleanup, shared-object boundaries and the separately managed setup client.
