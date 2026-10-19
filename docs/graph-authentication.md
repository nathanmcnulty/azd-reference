# Delegated Microsoft Graph authentication

`graph-delegated-authentication` coordinates a single operator-selected Microsoft
Graph PowerShell session. It is intentionally separate from deployment validation
and from solution-specific permission planning.

## Consumer responsibilities

The consuming solution must:

- calculate the complete permission set from its enabled features before calling
  the component;
- obtain the expected tenant from its trusted azd/Azure context;
- provide the exact expected administrator account selected for the run;
- provide a trusted solution-owned application client ID, independently of any
  inherited Graph context;
- choose a harmless read-only probe covered by the requested permissions;
- explicitly authorize an interactive broker/browser connection; and
- explicitly authorize replacing a mismatched inherited context.

The component does not discover permissions, install modules, acquire Azure CLI
tokens, build Graph requests, or disconnect an inherited session.

## Example

```powershell
$scopes = Resolve-AzdGraphScopeSet -Scope @(
    'Policy.Read.All'
    'RoleManagement.Read.Directory'
)

$session = Connect-AzdGraphSession `
    -TenantId $tenantId `
    -ExpectedClientId $solutionClientId `
    -Environment Global `
    -ExpectedAccount $administratorUpn `
    -Scopes $scopes `
    -ProbeUri '/v1.0/roleManagement/directory/roleDefinitions?$top=1&$select=id' `
    -AllowInteractive
```

Without `-AllowInteractive`, the command only inspects and probes an existing
context. It fails rather than opening authentication. A mismatched existing
tenant, client application, cloud, or account also requires `-AllowContextReplacement`; this prevents
an ordinary lifecycle hook from silently changing the operator's Graph identity.

The returned object contains tenant, verified `clientId`, environment, account,
context type, granted
scope names, and reuse/probe status. It never contains an access token.

Microsoft Graph PowerShell persists its secured token cache across sessions with
`ContextScope CurrentUser`. A later hook still performs a read-only probe because
cached metadata alone does not prove the current process has a usable token.

The component requires Microsoft.Graph.Authentication 2.30.0 or later and is
tested with 2.38.0. Installation and update policy remain solution-owned.

## Migrating from 0.x

Version 1.0.0 adds the mandatory `-ExpectedClientId` parameter. Before updating a
consumer, obtain the tenant-specific solution application's client ID through
that solution's trusted configuration or explicit application setup. Supply it
at every `Connect-AzdGraphSession` call site, including noninteractive lifecycle
hooks. Update mocks and saved test context fixtures to expose the same `ClientId`,
then synchronize the canonical 1.0.0 component and update the consumer lock using
the repository's synchronization tooling. Existing 0.x consumer locks remain
unchanged until the consumer is explicitly migrated.

The ID must be a nonempty GUID. The Microsoft Graph Command Line Tools application
(`14d82eec-204b-4c2f-b7e8-296a70dab67e`) is rejected; omitting the ID never selects
the SDK's default application. Never copy an inherited context's client ID into
the expected value merely to make validation pass. Application creation,
permission planning, and consent remain the consumer's responsibility.

The same client binding is checked before session reuse and after the one allowed
normal browser/broker connection. An otherwise matching context with an absent,
empty, malformed, or different `ClientId` is unusable and is never probed. An
interactive replacement still requires both `-AllowInteractive` and
`-AllowContextReplacement` for an inherited mismatched context. Failed post-connect
proof stops immediately without retry, device-code fallback, or global cache
clearing. SDK versions that cannot expose `ClientId` cannot prove this contract;
update the SDK through the consumer's normal installation policy rather than
skipping the check.
