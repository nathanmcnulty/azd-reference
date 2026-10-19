# Maester 2.3.0 permission review

The canonical [permission manifest](../components/powershell/maester-azd-hooks/Maester-GraphPermissions.json)
version 1.0.0 targets stable Maester **2.3.0**, not current `main`, `latest`, or
3.0 preview. It travels with the versioned Maester hooks component and is vendored
into consumers with their component lock. Changing its bytes changes the consent
plan digest; a reviewed plan cannot silently apply a different release inventory.

## Profiles and consent consequences

- **Full: 27 Graph application read roles.** The 25 default names returned by the
  actual 2.3.0 `Get-MtGraphScope`, reviewed against Microsoft's application
  permission column, plus the two endpoint-specific reads below.
- **Minimal: the original eight roles.** Same packaged assessment suite, fewer
  granted capabilities. Permission errors and skipped/not-run tests stay visible.
- **Extended: exact legacy 19-role inventory.** Retained for explicit compatibility,
  not an alias for Full. Existing access is not removed when selecting a smaller
  profile; revocation is separate work.
- **Mail.Send and ReportSettings.ReadWrite.All:** separate optional capabilities.
  The former sends mail. The latter lets an upstream assessment temporarily turn
  off tenant-wide usage-report privacy; restoration can fail. Neither belongs to
  the read-only profiles. Existing grants of this write role can still permit the
  upstream behavior, even if the new selection does not add it.

The migration from legacy Extended to Full has nine additional reads and one
legacy-only read (`PrivilegedAccess.Read.AzureAD`); do not silently revoke that
legacy grant. The old seven missing reads remain missing in Extended in 2.3.0:
AuditLog.Read.All, EntitlementManagement.Read.All, NetworkAccess.Read.All,
OnPremDirectorySynchronization.Read.All, OrgSettings-AppsAndServices.Read.All,
OrgSettings-Forms.Read.All, and RoleManagementAlert.Read.Directory.

### Why the two additional reads are necessary

1. **Policy.Read.DeviceConfiguration** covers the application-authenticated
   `GET beta/policies/deviceRegistrationPolicy` used by MT.1061, MT.1070,
   MT.1090 and MT.1091. `Policy.Read.All` is documented as an alternative for
   delegated access, not application access, on this endpoint.
   [Microsoft endpoint contract](https://learn.microsoft.com/en-us/graph/api/deviceregistrationpolicy-get?view=graph-rest-beta).
2. **Sites.Read.All** covers MT.1106's SharePoint site dereference while validating
   entitlement-management catalog resources. SharePointTenantSettings.Read.All
   does not cover it. This is broad access: it permits reading documents and list
   items across all site collections, beyond that test's site-existence check.
   Display this consequence before approval. Without suitable access the test can
   report an inaccessible site without reliably distinguishing denied access from
   a stale resource.
   [Microsoft site permissions](https://learn.microsoft.com/en-us/graph/api/site-get?view=graph-rest-1.0),
   [exact source](https://github.com/maester365/maester/blob/7413c42d3fcc724dfea94d2726e690ddd364d914/powershell/public/maester/entra/Test-MtEntitlementManagementValidResourceRoles.ps1).

Every grantable role records its **application** role ID. The IDs are not the
same as same-named delegated OAuth scopes. All 25 upstream default names have
application roles in the reviewed Microsoft reference, including both OrgSettings
reads. No delegated-only name has been converted to an invented application role.
`ChannelMessage.Send` remains delegated-only output capability.

## Coverage stays explicit

Full is a reviewed stable Graph permission baseline, not proof that every test
runs. Preserve the suite and existing upstream defaults: Preview and LongRunning
are opt-in; AD requires an explicitly connected supported host. Ambient drift is
excluded before discovery, with only the already-approved Container adapter
allowing its separately qualified suite. No permission-error blacklist is added.

The four preview reads (AgentIdentity.Read.All, AgentIdentityBlueprint.Read.All,
AgentIdentityBlueprintPrincipal.Read.All, Application.Read.All) are documented but
not grantable through these profiles. GSA MT.1193 needs Application.Read.All but
is itself Preview. Preview support needs a separate reviewed change.

Graph permission grants do not establish these service connections or roles:

- Exchange Online: Exchange.ManageAsApp on the Exchange resource and separately
  configured Exchange service-principal authorization, currently View-Only
  Configuration in these consumers
- Teams: separate Teams PowerShell authorization, currently Teams Reader
- Azure: Reader only at explicitly selected scopes
- Security & Compliance, SharePoint/PnP, Dataverse, GitHub, Azure DevOps and
  on-premises AD: additional supported connection and authorization requirements

Licensing, cloud availability, data availability and beta API behavior remain
runtime constraints. No official application-permission contract was located for
CISA's `beta/identityProtection/settings/notifications`; retain this as unverified
coverage rather than inventing a permission. Concealed report identities can also
limit MOERA classification without the separate privacy-write capability.

There is also a documented application-access mismatch for stable on-premises
synchronization checks: the permission reference defines the application role
`OnPremDirectorySynchronization.Read.All`, but both the
[v1.0 endpoint](https://learn.microsoft.com/en-us/graph/api/onpremisesdirectorysynchronization-get?view=graph-rest-1.0)
and [beta endpoint](https://learn.microsoft.com/en-us/graph/api/onpremisesdirectorysynchronization-get?view=graph-rest-beta)
mark application access unsupported. Maester's stable SoftHardMatching and
OnPremisesObjectIdentifierUpdatesBlocked checks call those respective endpoints.
The upstream read role stays in Full; its existence does not prove these checks
work app-only. Keep this coverage gap visible without adding writes or silently
removing the baseline role.

A readback of an app-role assignment does not prove that a cached managed-identity
token has refreshed. A successful job, valid HTML, or strict healthy assessment
receipt does not certify complete workload coverage or policy compliance.

## Release evidence

- Stable release: [2.3.0](https://github.com/maester365/maester/releases/tag/2.3.0),
  source commit `7413c42d3fcc724dfea94d2726e690ddd364d914`
- Official [Gallery package](https://www.powershellgallery.com/packages/Maester/2.3.0),
  `.nupkg` SHA-256 `95F720822D04271F5E15F4665BC017111DC72E17B97E5D0525CB4EC2FF5BD0B0`
- Bundled inventory: 519 test files, 524 total files, config version
  `2026.10.06.1`; all test files match the tagged source byte-for-byte. Only the
  packaged config's release/version fields differ from source.
- [Release-matched Get-MtGraphScope](https://github.com/maester365/maester/blob/7413c42d3fcc724dfea94d2726e690ddd364d914/powershell/public/Get-MtGraphScope.ps1)
- [Microsoft application/delegated permission reference](https://learn.microsoft.com/en-us/graph/permissions-reference),
  reviewed 2026-10-19; hash and per-role references are in the manifest

Static source/API review and offline tests establish the declared contract. They
do not constitute actual consent, tenant assessment, or native workload proof.
