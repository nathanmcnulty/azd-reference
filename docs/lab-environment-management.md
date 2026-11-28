# Lab environment management

`portfolio/lab-environments.example.json` is a machine-readable, reviewable
registry for lab ownership and observed Azure control-plane state. It is a
planning and reporting contract. It is not deployment input, a permissions
manifest, a secret store, or evidence that an environment is healthy.

The registry names the expected tenant, the target subscription, the
subscriptions that may be queried, and each solution's desired environment.
Each observed environment records its subscription, optional resource group,
source revision, validation status, and whether tenant objects are tracked.
`tenantObjectsTracked` is a declaration of tracking scope. It never proves
that an object exists or that a deployment works. A `tenant` row with no
resource group is reported as `tenant-only`; a non-tenant row with no resource
group is reported as `unmapped`. Neither is reported as a working resource
environment.

## Read-only status

Use fixture data for offline review and tests:

```powershell
./tooling/Get-AzdLabEnvironmentStatus.ps1 `
  -RegistryPath ./portfolio/lab-environments.example.json `
  -InventoryDirectory ./tests/fixtures/lab-environment-inventory `
  -OutputPath ./lab-environment-status.json
```

Fixture files are named `groups-<subscription-id>.json` and
`resources-<subscription-id>.json`. A missing or invalid file is reported as
unknown or failed coverage and resource counts remain null. Empty arrays are
valid evidence of a successful query; missing files are not treated as empty.
The repository does not bundle lab inventory. The caller must populate the
directory with saved arrays whose subscription IDs match the registry being
reviewed; the placeholder example therefore requires caller-supplied fixture
files before it can produce complete coverage.

Without `-InventoryDirectory`, the tool performs read-only Azure CLI calls.
It first reads the cached account list and requires every declared
subscription to appear with the exact registry tenant. It then invokes only
`az group list --subscription <id> --output json` and
`az resource list --subscription <id> --output json`. Every resource query
uses its explicit subscription. The tool does not log in, change the default
subscription, run repository commands or hooks, read secrets, deploy, or
delete resources. Azure command output is parsed locally; command errors are
reported without relaying stderr content.

`coverage` is `complete`, `unknown`, or `failed`. Unknown and failed coverage
produce a nonzero exit status. `present` means only that the declared resource
group was returned by a successful group query. It does not certify runtime
health, endpoint behavior, identity authorization, or human-visible output.
Extra resource groups and resources are `unmapped`. Resources are counted as
tracked when their resource group maps to a declared environment; resources
in extra groups are untracked. Tag drift is reported separately for the
required ownership markers and for optional compatibility markers. If
`-OutputPath` is supplied, it must name a new file and cannot refer to the
registry; existing reports are preserved.

The required tags are:

- `solution`
- `lab-environment`
- `owner`
- `cost-center`
- `portfolio`

Existing `environment` and `managed-by` tags are retained as optional
compatibility markers and are reported separately. Registry rows can provide
`desiredTags` to set reviewed values; otherwise the tool uses the solution and
environment names, `unassigned` for owner and cost center, `azd` for
portfolio, and `azd` for the compatibility marker.

## Subscription operating constraints

The optional `subscriptionPolicies` array records reviewed planning
constraints per declared subscription. Each entry names the subscription,
display name, `primary` or `support` role, monthly credit, budget name and
amount, and a planning ceiling. The schema requires positive amounts; the
status tool also requires unique policy subscription IDs, requires each ID to
appear in `subscriptions`, and rejects a planning ceiling above monthly
credit. Older registries without this array remain valid.

The status report labels these values `planned-only`. They are surfaced for
budget and placement decisions and do not measure remaining credit, spending,
budget forecast, or Azure billing state. No billing API, secret, or credit
balance is read.

## Identity and resource boundaries

Each repository and environment should use its own OIDC deploy identity. The
identity is scoped to the resource group it deploys, with the repository and
environment encoded in its federated credential subject. A deployment receipt
records the exact source revision, tenant, subscription, resource group, and
identity used. A receipt is evidence about one operation; it does not replace
the registry or prove later state.

Runtime identities are separate from deployment identities and receive only
the data-plane access needed by the running workload. A GitHub App is used for
repository operations only, installed on explicitly approved repositories. It
does not receive Azure, Microsoft Graph, Actions administration, or unrelated
repository permissions.

Logs can use a shared workspace for centralized investigation. Storage,
Key Vault, and compute remain per workload so data, secrets, and runtime
failure boundaries stay isolated. Shared logging does not grant a workload
access to another workload's data or keys.

## Deployment identity plan

Generate a review-only identity plan for one exact registry row with:

```powershell
./tooling/Get-AzdLabDeploymentIdentityPlan.ps1 `
  -RegistryPath ./portfolio/lab-environments.example.json `
  -SolutionId <solution-id> `
  -EnvironmentName <azd-environment> `
  -GitHubEnvironment <github-environment> `
  -OutputPath ./lab-deployment-identity-plan.json
```

The plan requires an `azure` solution, a unique exact environment binding,
declared subscription membership, a non-null workload resource group, and a
40-hex source revision. It places a deterministic user-assigned managed
identity in `rg-azd-lab-management` in the registry target subscription and
binds the exact GitHub OIDC subject
`repo:owner/repository:environment:<github-environment>`. The plan proposes
Contributor at the workload resource-group scope and marks it ungranted;
the tooling does not call Azure or GitHub and never creates identities,
credentials, role assignments, policies, or hooks.

`OutputPath` must name a new file in an existing directory. The tool refuses
to overwrite the registry or an earlier report; use a new receipt filename
for each review.

The [identity Bicep template](../infra/lab-deployment-identity/main.bicep) follows the same management-resource
group placement and defaults its Contributor grant to disabled. It fails
closed for an equal management/workload scope by suppressing the grant. A
plan or template output does not prove local source cleanliness, revision
validity, default-branch protection, live OIDC exchange, or role propagation.
Graph permissions and workload bootstrap remain separate review gates.

The [manual identity check](../templates/workflows/azd-lab-identity-check.yml)
is a standalone workflow template. It uses an immutable Azure Login revision,
the `lab` environment, and a `main` branch guard. Its only Azure reads verify
the login identity, tenant, subscription, and workload resource group. It does
not check out or run deployment code. Copy it into a reviewed solution before
dispatching it; preparing this file is not evidence of an OIDC token exchange.
The four environment variables are `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
`AZURE_SUBSCRIPTION_ID`, and `AZURE_WORKLOAD_RESOURCE_GROUP`; none is a client
secret. Bootstrap identities should supply a reviewed `owner` tag explicitly.

## Source truth and migration gates

The solution repository and its immutable source revision are the source of
truth for deployable code. The registry is the source of truth for the
reviewed lab target and observed ownership mapping. Azure control-plane reads
are observations. Deployment receipts bind an operation to its source,
identity, tenant, subscription, and resource group.

Before migrating a solution, review the registry row, confirm the exact
repository revision, create the repository/environment OIDC identity with
resource-group scope, and capture a receipt from a dry-run or controlled
deployment. Then verify control-plane resources, required tags, logs, and
runtime identity boundaries independently. Endpoint or user-visible tests are
separate gates. A migration remains pending until these gates and the
solution's own offline and live validation evidence are reviewed; this
document does not assert that any particular lab migration is complete.
