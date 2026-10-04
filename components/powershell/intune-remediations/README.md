# Intune Remediations deployment (pilot)

Vendor this component at an immutable revision. It publishes independently
packaged, self-contained Windows data-gathering scripts through an explicitly
supplied Microsoft Graph caller. It does not authenticate, grant permissions or
fetch script dependencies at runtime. Consumer solutions own their collector
source and package-building logic.

Use `Import-IntuneDeviceHealthScriptPackage` to verify package files, then
`Invoke-IntuneDeviceHealthScriptPublication` to prepare a review result. Execution
requires the explicit execution switch and exact caller/target tenant values.
Choose All devices or a named group explicitly. Packages use SYSTEM, 64-bit
Windows PowerShell and a daily UTC detection-only schedule. The companion
remediation is dormant. Consumers must validate endpoint
scripts on Windows PowerShell 5.1; PowerShell 7.4 authoring checks are separate.

`Get-IntuneDeviceHealthScriptReadback` exports control-plane configuration,
assignments and device run states. A successful create or matching assignment
does not prove delivery or execution. Intune output is bounded; consumers must
report overflow and failed/partial collections rather than treating missing
values as an empty inventory. Complete inventories can remain local when they
exceed the service output limit.

The operator's Graph requirements are recorded in each consumer permission
manifest. Existing cached consent is not least-privilege proof. Hosting snapshot
engines does not require this publisher's write permission, and manifests never
authorize granting permissions.

`Request-IntuneCollectorRun.ps1` is optional validation for one exact Windows MDM
endpoint, bound by both managed-device and expected Entra-device IDs. It verifies
the package content, remote script identity, execution flags and bytes, and
unfiltered All devices detection-only scheduled assignment before requesting a
run. On-demand execution can run the remediation companion when detection exits
1; this helper therefore accepts only the exact hash-locked AV and Firewall no-op
companions reviewed in this component. A manifest behavior label alone is
insufficient. It
requires an explicit execution switch and the additional delegated permission
`DeviceManagementManagedDevices.PrivilegedOperations.All`. A new receipt path is
required; the attempted request is saved before POST. An accepted request is
not proof that the endpoint ran the script. Supply caller tenant assertions from
the authenticated transport context; this component cannot inspect an arbitrary
scriptblock's token.

The package `version` is authoring metadata. Intune's observed custom-script service
version is an independent positive integer; it is not submitted or compared to the
package version. Reuse approvals bind the observed service version in the full
current-state digest. Exact script bytes, identity, flags, parameters, scope tags
and schedule remain required.
