# Delegated Graph authentication changelog

## 1.0.0

- Breaking: require an explicit `ExpectedClientId` GUID for a solution-owned
  public client; empty IDs and Microsoft Graph Command Line Tools are rejected
  before any Microsoft Graph command runs.
- Bind both inherited and newly connected delegated contexts to that application
  in addition to tenant, account, cloud, context type, and complete scope set.
  Missing or invalid context client IDs fail closed before the read-only probe.
- Pass `ClientId` explicitly to the single normal browser/broker connection and
  return the verified `clientId` in the session result.
- Migration: configure the solution's tenant-specific application client ID and
  pass it as `-ExpectedClientId` at every call site. Update consumer wrappers and
  deterministic context fixtures together, then resynchronize the versioned
  component and lock. Do not derive the expected ID from an inherited context.
  See [the migration guide](../../../docs/graph-authentication.md#migrating-from-0x).

## 0.2.0

- Require PowerShell 7.6 or later. The public commands and data contracts are unchanged.

## 0.1.1

- Add release metadata without changing the authentication API.
- Retain the exact context, scope, account, and read-only token proof behavior from 0.1.0.

## 0.1.0

- Introduce one-session delegated Microsoft Graph authentication coordination.
