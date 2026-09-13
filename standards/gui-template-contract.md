# GUI template contract

`azd-gui.json` is an optional, template-root deployment description for Azure
Deployment Studio. It is descriptive input to the GUI; `azure.yaml`, Bicep,
and checked-in lifecycle scripts remain the executable source of truth.

The GUI schema is owned by `azd-gui`. This repository does not copy or publish
that schema. The compatibility reference for this initial standard is
`azd-gui` commit `3ee9d5f2b162b441e5d86f0baed3091dad18fb6d`,
`schemas/azd-gui.schema.json`, SHA-256
`dbfc8cc53878ee7a52c91d8d47e72f8f451cad74eb07ff82457a5f97721cb233`.
This exact revision includes conditional feature requirements, the
security-group picker, and the external-template preparation gate. A stable
public schema URL is pending while `azd-gui` remains private.

## Three catalog boundaries

These files answer different questions and must not be substituted for one
another:

| Artifact | Owner and purpose | Execution boundary |
| --- | --- | --- |
| `.azd/catalog.json` | A solution-owned descriptive catalog for title, summary, tags, highlights, and quick-start documentation. | Display-only. `quickstartCommands` are documentation and must never be run by the GUI. |
| GUI pinned catalog | A GUI publisher-owned gallery index that selects a repository, exact commit, optional subdirectory, and currently either a bundled or origin-constrained sidecar manifest. | The GUI resolves and materializes the exact commit before deployment. A gallery entry is not a substitute for reviewing the template. |
| `azd-gui.json` | The desired embedded template deployment contract for prerequisites, connections, configuration fields, and registered read-only permission checks. | It is intended to be read from the selected template revision. It neither changes template code nor authorizes hooks, provisioning, or tenant writes. |

An external gallery is discovery metadata. Preparation resolves the selected
repository, exact commit, and optional subdirectory into one retained checkout.
For an external entry, it verifies the catalog-declared `manifestSha256` for
the reviewed sidecar, then requires that sidecar to be byte-identical to the
embedded `azd-gui.json` in the pinned selected subdirectory. Template authors
who publish a sidecar must embed those exact same manifest bytes in the selected
template revision.

The GUI derives the effective contract from that checkout and compares it with
the reviewed sidecar contract, including detected interactive lifecycle hooks.
It performs these checks before creating a destination, registering a project,
or starting azd initialization, and retains the verified checkout for
preparation. A gallery
entry still is not a substitute for source review.

Catalog digest checks establish consistency with the accepted catalog and the
pinned checkout at preparation time. They do not establish publisher
authentication, prove later mutable project content, or repair old registered
projects whose contracts were accepted before this gate. Previously accepted
external catalogs without sidecar digests require a fresh review. The GUI
retains these sources in Settings and can reapply a reviewed contract only to
an existing project with the same template ID and commit.

## Embedded manifest rules

The manifest requires `schemaVersion`, `prerequisites`, `connections`, and
`configuration`. Declare only settings that map to a template-owned azd
environment variable. Do not duplicate native GUI controls for tenant,
subscription, location, resource group, or environment name as custom fields.
Prerequisites, connections, and registered permission checks may declare an
optional boolean `condition`, for example
`{ "field": "includeExchange", "equals": true }`. The controller must be an
unconditional, non-sensitive boolean configuration field with an explicit
boolean default. Conditions support strict `true`/`false` equality only; native
validation rejects strings and other value types. Feature groups containing
controllers appear before the readiness gates they control, so an
administrator chooses optional components before tools, connections, and
read-only checks are evaluated. Keep baseline access requirements
unconditional: disabling an optional feature must never remove the Azure or
Graph access needed by the template's baseline setup.

An optional `lookup: "securityGroup"` is permitted only on a non-sensitive
`entraObject` configuration field. It is a wizard convenience for selecting a
security-enabled Entra group; the selected value remains the group object ID
that the template maps to its declared environment variable. The wizard uses a
tenant- and subscription-bound prefix search after at least two non-control
characters, returns at most 25 validated ID/display-name pairs, and requires an
administrator to explicitly select a returned ID because display names are not
unique. It clears every lookup ID, including a manually entered ID, when either
target changes. It uses the cached Azure CLI session for read-only public
Microsoft Graph requests only. It must not start a login,
request or grant permissions, expose tokens, or follow Graph pagination links.
If the lookup is unavailable or does not find the intended group, retain manual
object-ID entry as the administrator-reviewed fallback; do not infer a group.

`skeleton/azd-gui.json` intentionally has an empty `configuration.groups`
array. Its only parameters are `AZURE_ENV_NAME` and `AZURE_LOCATION`, supplied
by native azd target controls through `infra/main.parameters.json`.

The prerequisite list must cover tools required by lifecycle scripts as well
as provisioning. The skeleton declares PowerShell because `azure.yaml` runs a
PowerShell postprovision hook and Azure CLI because that hook's default
validation uses `az account show` and `az group show`. A manifest must not
claim a minimum version that the template has not established.

Connections explain why a cached session is needed. They must not initiate a
login, include credentials, or request device-code authentication. Registered
permission checks are read-only preflight evidence. A successful check does
not prove that a user can safely perform later directory or resource writes.
For the Maester pilot, the optional `ExchangeOnlineManagement` PowerShell
module prerequisite is conditioned on `includeExchange == true`. Its
installation remains a manual, operator-reviewed step. The baseline Azure
CLI, Azure Developer CLI, and PowerShell prerequisites and baseline access
checks remain required when Exchange, Teams, Azure, or dashboard components
are disabled.

## Hooks and optional features

`azure.yaml` is authoritative for lifecycle hooks. Keep hook commands public,
checked in, and reviewable. Set `requiresInteractiveTerminal` accurately so
the GUI can route an interactive template to an external terminal; it does not
make a hook safe or noninteractive. The skeleton hook is noninteractive and
runs the default read-only validation mode.

For an optional feature, define a configuration field only when it maps to a
real environment variable. Its condition, default, allowed values, affected
components, required permissions, lifecycle hooks, outputs, validation checks,
and receipt details must agree with the template implementation. Do not infer
optional behavior merely from a component lock: the lock records provenance of
vendored files, not selected feature state.

Optional `recommendationProfiles` provide explicit starting points with `id`,
`title`, `description`, and a `values` map keyed by configuration field IDs.
Explain identity permissions, optional resources, and operational consequences.
Profiles cannot set secrets, sensitive fields, or standard target/source values.
They must match declared field types, options, and supported validation rules.
Keep template defaults intact: the administrator applies a profile and reviews
the resulting choices before execution. A minimal profile is not a promise of
zero required permissions.

## Receipts and validation

Use the existing deployment receipt contract for intended and applied actions,
artifacts, summary counts, and outstanding operational actions. Use
`scripts/Test-Deployment.ps1` and the deployment-validation report for checks
that actually ran. Do not introduce a second GUI receipt shape.

When target binding is necessary, place a solution-owned, namespaced record in
the receipt `details` object with the immutable template revision, selected
environment identifier, and only the nonsecret target identifiers needed for
audit. Do not include tokens, callback URLs, connection strings, or unnecessary
tenant data.

## Validation and current limits

The reference repository validates its skeleton manifest with an offline
Pester contract test. It deliberately does not carry a duplicate GUI schema.
Cross-repository JSON Schema validation is an optional compatibility gate: an
integrator may obtain the cited `azd-gui` revision, verify its recorded hash,
and run `Test-Json` against that repository's schema before accepting a schema
change.

Current manifest limits are intentional: it does not prove hook behavior,
derive configuration from Bicep, verify write permissions through tenant
mutation, or replace source review. The GUI must preserve the exact
template/target approval boundary before provisioning or deployment.
