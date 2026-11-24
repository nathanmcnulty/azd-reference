# Maester target context: 1.0.0 caller migration

This source-only `maester-azd-hooks` candidate addresses reference issue [#110](https://github.com/nathanmcnulty/azd-reference/issues/110), from reference main `3f88050332f9647da5e3bc8044f87cf2c7101c08` (0.1.7). The component remains **pilot**. The major version follows the component lifecycle contract because callers must supply previously optional context. It does not publish a tag/release, advance any portfolio desired version, update consumers, or establish live Azure acceptance.

## Fresh subscription contract

`Get-AzCliSubscriptionContext -SubscriptionId <guid> [-TenantId <guid>]` performs a fresh explicitly subscription-scoped ARM GET for `/subscriptions/<guid>?api-version=2022-12-01`. CLI account listing/show and the global default are not current-state evidence. The helper requires matching `subscriptionId` and ARM `id`, a non-empty tenant GUID and display name, and exact state `Enabled`. Failed reads, malformed/missing metadata, unknown states, disabled subscriptions, and mismatches terminate.

The return object retains the hook-facing account shape: `id` is the subscription GUID (not ARM's resource path), `name` is the display name, `tenantId` is the tenant GUID, and `state` is `Enabled`. Cache-only account fields such as `isDefault`, `user`, and `environmentName` are not part of this return contract. An omitted expected tenant allows read-only discovery of that explicitly selected subscription's current tenant; callers performing writes must supply the expected tenant. No helper changes the CLI global default.

The ARM endpoint is Azure public cloud, matching the component's existing Graph and Outlook endpoints. Sovereign-cloud support is not introduced. Subscription metadata readers need permission to read the selected subscription. Offline source tests do not prove that access or any Azure operation succeeded.

## Preup migration

When `AZURE_RESOURCE_GROUP` is selected, supply `AZURE_SUBSCRIPTION_ID` and `AZURE_TENANT_ID` before preup. For each setting a nonblank process environment value takes precedence over the selected azd environment. A missing expected tenant fails closed. The fresh shared guard runs before checking or creating the group. An unknown group-existence response also fails closed. `AZURE_LOCATION` remains required only when creation is needed. With no selected resource group, preup remains a no-op.

## Token and Exchange caller migration

- `Get-AzCliAccessToken` requires a non-empty GUID in `TenantId` or `SubscriptionId`. Missing/invalid input throws before token acquisition. A subscription selector is checked through the shared current ARM guard. When both selectors are supplied, the guard verifies their relationship, then the token command uses only `--subscription` because Azure CLI treats those token selectors as mutually exclusive.
- Tenant-only requests use `--tenant`. Token responses must contain a nonblank access token and matching `tenant`; subscription-scoped responses must also match `subscription`. Acquisition failures or invalid response scope return null, never an ambient token.
- `Connect-ExchangeOnlineSilent -Organization <domain> -TenantId <validated-tenant-guid>` requires explicit `TenantId`. `Organization` retains its original parameter position and meaning; it is not a substitute for tenant context. Existing callers omitting `TenantId` now terminate before connecting. Obtain and validate the selected subscription/tenant context before any host-specific Exchange role mutation, and pass that tenant into this helper.
- There is no interactive Exchange fallback. If an explicitly tenant-scoped Outlook token cannot be acquired, the helper terminates with `az login --tenant <tenant-id>` guidance using normal broker/browser authentication. It cannot return success from an unverified fallback session.
- `Confirm-AzureLogin` now requires a tenant GUID and never probes or logs in with an implicit default. Graph callers must continue forwarding their explicit tenant.

Consumer adoption must update host-specific Exchange call sites and their behavioral tests separately; this change deliberately edits no consumer repository. All eight managed file paths remain in the component manifest. Other managed source files and Minimal/Extended/Mail.Send/explicit Graph role selections are unchanged.

## Qualification boundary

The offline suite executes the actual preup, subscription, token and Exchange helpers with fail-closed command doubles. It covers different ambient/default context, stale Enabled cache versus disabled ARM state, malformed and missing metadata, tenant/subscription mismatches, scoped Outlook tokens, and blocked Exchange continuation. Syntax/analyzer, component version, release-integrity and synchronization/drift checks qualify source only. Azure validation belongs to the originating session; no Azure access, real tokens, grants, resources or delivery are needed here.
