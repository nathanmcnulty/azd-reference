# Changelog

## 3.0.0 - 2026-10-19

- Breaking: replace configuration/name-based best-effort cleanup with ownership-receipted lifecycle hooks. Legacy or ambiguous ownership blocks automatic down instead of guessing what to delete.
- Persist each approved external write intent and exact response identity under a selected-environment lifetime lock; preserve earlier records on failures and no-op reruns.
- Capture fresh dedicated resource-group creation only from an exact ARM 201 response and bind declared infrastructure IDs. Reused groups, foreign listed resources/locks, changed source and uncertain outcomes fail closed.
- Separate explicit owned-lock approval in predown from fresh-approved external cleanup in postdown after exact ARM absence. Canceling azd leaves external authorization unchanged; separately approved unlocks remain removed.
- Preserve external administrator setup clients and adopted/shared objects. Unsupported shared restoration remains a visible blocker; no implicit extra Graph consent or runtime self-grant authority.
- See [ownership lifecycle and recovery boundaries](../../../docs/maester-owned-lifecycle.md). Source qualification does not establish live provider cleanup or actual azd cancellation behavior.

## 2.1.0 - 2026-10-19

- Pin Maester setup to process-scoped token caching through coordinator 1.1.0. Refuse inherited non-Process contexts rather than risk SDK failure cleanup against a persistent context; document SDK shared-record/internal-fallback limitations.

- Add an explicit federated-application runtime target contract while retaining managed identity as the default. Bind tenant-local application/service-principal IDs and an exact issuer, subject and token-exchange audience before planning grants.
- Include all preserved federated trusts and nonsecret application/service-principal credential metadata in the reviewed plan hash. Never grant assessment roles to the captured setup client.
- Require the host to validate its deployment endpoint independently; application registration, service-connection creation and federated trust establishment require separate approved bootstrap plans.
- Keep the same Maester 2.3.0 permission manifest and optional-capability boundaries. No runtime self-grant permissions or automatic bootstrap are added to the canonical helper.

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
