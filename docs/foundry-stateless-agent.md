# Optional stateless Foundry prompt agent

`foundry-stateless-agent@0.1.1` is a source-only pilot. It uses the existing
component manifest, immutable source revision, SHA-256 lock, synchronization and
drift checks. It is not a new deployment framework or a signed component release.
Exchange is the first planned consumer; a generic report-advisory consumer is the
second reviewed shape. Neither is evidence of live Foundry acceptance.

## Boundary

The component owns three vendored files: one optional Bicep module and a
PowerShell 7.6 module/manifest. The consumer owns its prompt, output JSON schema,
data minimization, authentication, reviewed configuration, lifecycle hooks,
cost/budget policy, result storage and all domain decisions. A recommendation
never constitutes approval or permission to change tenant policy.

The Bicep module creates a new Foundry account, project and exact-version model
deployment only when `enabled=true`. It disables local/key authentication and
uses a public authenticated endpoint; private networking is not implemented.
The default is `gpt-6-luna`, catalog version `2026-09-22`, capacity 1 with
`GlobalStandard`. Name, version, region, SKU and capacity are configurable; the
consumer must verify availability, quota, cost and data-processing geography
before deployment. There is no automatic model/region/SKU fallback or upgrade.
`store=false` does not remove the provider's separate abuse-monitoring or other
service-retention obligations.

The new project's managed identity receives Foundry User on its own new account
for model access. An explicitly supplied setup principal optionally receives
Foundry User on the project; omit it if existing rights suffice. There is no
collector/runtime principal parameter or permission union, and no Graph,
Exchange, Storage tool, connection, memory store or vector store is provisioned.
The account/project IDs and project endpoint are outputs for exact readback.

## Same-azd-up integration

1. Vendor the component from the reviewed full source commit with
   `Sync-AzdComponent.ps1 -Component foundry-stateless-agent -Revision <40-hex-sha>`.
   Commit the files and generated `azd-components.lock.json`. Deployment must not
   contact Reference or a sibling repository.
2. Let the consumer's configuration wizard choose the optional feature, model
   parameters, data boundary and named agent. Pass `enabled=false` by default to
   its Bicep module. Keep core collection/review usable without Foundry.
3. In the existing postprovision hook, attest the selected Azure cloud, tenant,
   subscription and operator account. Reuse the normal Azure CLI/Az PowerShell
   session and acquire a short-lived token for `https://ai.azure.com/`. Never
   trigger another login, use device-code flow or store/log the token in this
   component. Pass it as a `SecureString`.
4. Build the definition with `New-AzdFoundryAgentDefinition`. Supply a bounded
   solution-owned prompt and strict object JSON schema. Only local `#/$defs/`
   schema references are allowed. The definition has no tools.
5. If a protected deployment receipt already identifies an exact agent version,
   call `Test-AzdFoundryAgentVersion` with that version and the current definition.
   Reuse only on exact readback. A changed prompt/model/schema needs an explicitly
   reviewed new version through `Publish-AzdFoundryAgentVersion`. That command
   creates once, GETs the returned exact name/version and checks every reviewed
   definition field; unreviewed non-null service fields fail closed. An uncertain
   POST/readback outcome is not retried automatically. Reconcile it before
   creating another version. `-WhatIf` makes no HTTP call.
6. Persist the metadata-only verified receipt with the solution's protected
   deployment configuration. It records endpoint, name, version, model deployment
   and definition hash. It is not a signature, approval, actor identity or proof
   that an arbitrary editable JSON document came from this hook.
7. Invoke one response with `Invoke-AzdFoundryStatelessResponse`, independently
   providing the deployment endpoint, exact name/version and definition plus the
   verified receipt. The function compares all bindings before HTTP. Saved agent
   versions are immutable, so runtime does not need agent-definition GET rights.
   A mismatch blocks the request.

The response request uses `agent_reference` with an explicit version on
`/openai/v1/responses`, with `store=false`, `background=false`, `stream=false`,
no tools and no conversation or previous-response ID. There is one synchronous
POST, with no implicit retry. The module rejects incomplete/failed/stored/linked
responses, tool calls, refusals, unexpected output items and schema-invalid
output. It handles reasoning items without mistaking the first output item for
text. The caller receives the parsed result separately from its metadata receipt.

Limits are 64 KiB UTF-8 input, 32 KiB schema, 16,384 instruction characters,
1 MiB HTTP response and 64 KiB output text. `max_output_tokens` defaults to 2,048
and is bounded to 256–8,192. Byte/character limits are not input-token counts;
optional returned token-usage metadata supports consumer budget accounting.
HTTP redirects and cookies are disabled. Tokens and raw service errors are not
returned. Public Azure project endpoints only are supported in this pilot.

## Authority and qualification

Setup version creation/readback needs Foundry project data-plane authority;
Azure resource Contributor alone is insufficient. Foundry User is a documented
setup role. Foundry Agent Consumer guarantees interaction with agent endpoints;
it is not evidence that the exact-version project Responses route has the same
permission boundary. This pilot does not silently grant Foundry User to the
worker to bypass a 403. Keep initial use with the explicitly authorized operator,
or separately qualify a least-privilege runtime role and record its exact data
actions before unattended invocation. Do not replace exact-version requests with
a mutable active-version endpoint without a separately reviewed contract.

Repository tests establish source behavior, HTTP payloads using mocks, manifest
shape and exact vendoring/drift. They do not prove regional deployment, role
propagation, agent/model availability, live structured output or a runtime
identity's access. Keep the optional feature unready when any step is unverified.
Teardown preserves the consumer's evidence and follows exact ownership; no API
that deletes a shared agent/account is exposed by this module.

## Second consumer shape

A report-only security solution can vendor the same module, provide its own
sanitized aggregate findings and JSON summary schema, and retain recommendations
beside its existing reports. It reuses no Exchange prompt, permission or state.
This reviewed shape justifies a pilot boundary, not production promotion or an
automatic rollout to existing solutions.

## Sources checked 15 October 2026

- [Foundry REST v1 agent and Responses contracts](https://learn.microsoft.com/en-us/rest/api/microsoft-foundry/aiproject)
- [Responses without storing](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/runtime-components#generate-a-response-without-storing)
- [Immutable agent versions](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/configure-agent)
- [Foundry RBAC and consumer/author separation](https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry)
- [GPT-6 Luna catalog/version](https://ai.azure.com/catalog/models/gpt-6-luna)
- [Foundry project Bicep contract](https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/2025-06-01/accounts/projects)
