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
    -Environment Global `
    -ExpectedAccount $administratorUpn `
    -Scopes $scopes `
    -ProbeUri '/v1.0/roleManagement/directory/roleDefinitions?$top=1&$select=id' `
    -AllowInteractive
```

Without `-AllowInteractive`, the command only inspects and probes an existing
context. It fails rather than opening authentication. A mismatched existing
tenant, cloud, or account also requires `-AllowContextReplacement`; this prevents
an ordinary lifecycle hook from silently changing the operator's Graph identity.

The returned object contains tenant, environment, account, context type, granted
scope names, and reuse/probe status. It never contains an access token.

Microsoft Graph PowerShell persists its secured token cache across sessions with
`ContextScope CurrentUser`. A later hook still performs a read-only probe because
cached metadata alone does not prove the current process has a usable token.

The component requires Microsoft.Graph.Authentication 2.30.0 or later and is
tested with 2.38.0. Installation and update policy remain solution-owned.
