# GUI template contract

`azd-gui.json` is an optional, template-root deployment description for Azure
Deployment Studio. It is descriptive input to the GUI; `azure.yaml`, Bicep,
and checked-in lifecycle scripts remain the executable source of truth.

The GUI schema is owned by `azd-gui`. This repository does not copy or publish
that schema. The compatibility reference for this initial standard is
`azd-gui` commit `fec8f72ca65a1028d491e137d40db83f528787ec`,
`schemas/azd-gui.schema.json`, SHA-256
`d2ce9cb480d074fcb2d19bcb0d59b8904106c3beaececc34b44a729d1761a28e`.
That is a reviewed source reference, not a public schema URL. A stable public
schema URL is pending while `azd-gui` remains private.

## Three catalog boundaries

These files answer different questions and must not be substituted for one
another:

| Artifact | Owner and purpose | Execution boundary |
| --- | --- | --- |
| `.azd/catalog.json` | A solution-owned descriptive catalog for title, summary, tags, highlights, and quick-start documentation. | Display-only. `quickstartCommands` are documentation and must never be run by the GUI. |
| GUI pinned catalog | A GUI publisher-owned gallery index that selects a repository, exact commit, optional subdirectory, and currently either a bundled or origin-constrained sidecar manifest. | The GUI resolves and materializes the exact commit before deployment. A gallery entry is not a substitute for reviewing the template. |
| `azd-gui.json` | The desired embedded template deployment contract for prerequisites, connections, configuration fields, and registered read-only permission checks. | It is intended to be read from the selected template revision. It neither changes template code nor authorizes hooks, provisioning, or tenant writes. |

An external gallery is discovery metadata. The desired deployment decision binds
the catalog entry, repository, commit, subdirectory, and embedded manifest bytes
to the same reviewed template revision. This binding is not yet implemented for
current external gallery sidecar manifests: they require a catalog-declared
`manifestSha256` digest of their exact served bytes and must remain on the same
HTTPS origin, but are not bound to the selected repository commit. Treat them as review metadata, not the
deployment control, until that binding exists. Direct GitHub inspection already
reads an embedded manifest at its resolved commit.

Catalog digest checks establish consistency with the accepted catalog, not
publisher authentication or agreement with executable template code. Previously
accepted external catalogs without sidecar digests require a fresh review. The
GUI retains these sources in Settings and can reapply a reviewed contract only
to an existing project with the same template ID and commit.

## Embedded manifest rules

The manifest requires `schemaVersion`, `prerequisites`, `connections`, and
`configuration`. Declare only settings that map to a template-owned azd
environment variable. Do not duplicate native GUI controls for tenant,
subscription, location, resource group, or environment name as custom fields.

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
