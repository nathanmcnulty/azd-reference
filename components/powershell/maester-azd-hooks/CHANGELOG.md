# Changelog

## 2.0.0 - 2026-10-19

- Breaking: use the tenant-owned delegated setup client with explicit tenant/account/client binding and the canonical Graph coordinator; remove Azure CLI Graph tokens and the global SDK command shadow.
- Collect Full/Minimal explicitly, preserve legacy Extended, and keep mail and report-setting writes separate.
- Load the reviewed Maester 2.3.0 permission manifest and plan exact managed-identity application-role deltas before writes. Require current plan approval for every expansion; preserve existing grants and verify exact readback.
- Require setup client bootstrap by an authorized administrator; runtime managed identities cannot self-consent.
- See [consent flow and migration](../../../docs/maester-consent-flow.md). Source-only pilot; no automatic existing-consumer adoption or live qualification.

## 1.0.0 - 2026-10-18

- Breaking: require explicit tenant/subscription scope for token requests and an explicit TenantId for Exchange connections; remove unverified interactive Exchange fallback.
- Validate current ARM subscription identity, tenant and Enabled state with an explicitly scoped fresh read before preup can create a resource group.
- Require AZURE_TENANT_ID for targeted preup, honoring the process environment before the selected azd environment.
- Preserve account-shaped id, name, tenantId and state fields for callers; reject missing/invalid context and token response scope metadata.
- Require a tenant for the Azure login helper and provide normal broker/browser login guidance without device-code authentication.
- See [caller migration](../../../docs/maester-target-context.md). This is a source-only pilot candidate; no release, consumer adoption or Azure validation is implied.

## 0.1.7 - 2026-10-15

- Bind every Graph permission lookup, assignment page, grant and readback to the explicitly selected tenant.
- Enumerate all existing assignments with bounded, same-collection HTTPS continuation handling before granting.
- Validate requested enabled application roles before mutation and verify exact assignment tuples before reporting completion.
- Preserve the Minimal, Extended, Mail.Send and explicit role selections.

## 0.1.6 - 2026-10-07

- Validate the optional Web App security group Object ID as a non-empty GUID before persisting wizard settings.
- Give interactive users group lookup and Web App skip guidance while keeping non-interactive failures explicit.

## 0.1.5 - 2026-09-20

- Avoid passing mutually exclusive tenant and subscription selectors to Azure CLI token acquisition.

## 0.1.4 - 2026-09-20

- Allow Azure CLI access-token requests to target an explicit subscription.

## 0.1.3 - 2026-09-20

- Retry Azure DevOps service-connection deletion while pipeline cleanup is asynchronous.

## 0.1.2 - 2026-09-20

- Preserve pre-existing Azure DevOps repositories during environment teardown.

## 0.1.1 - 2026-09-20

- Retry managed identity principal discovery while ARM identity propagation completes.

## 0.1.0 - 2026-09-19

- Initial pilot release extracted from the azd-maester shared hook and permission helpers.
