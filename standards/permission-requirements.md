# Permission requirement tracking

Each independently deployable solution owns `azd-permissions.json`, validated by
`schemas/permission-requirements.schema.json`. This is review and comparison
metadata. Deployment hooks must not use it to grant permissions automatically.
Catalog display metadata remains separate.

Record each requirement with its resource API, permission kind, exact name,
logical principal, lifecycle phase, feature switch, default selection, scope,
rationale, and evidence. Separate delegated scopes, application roles, Azure
RBAC, Entra roles, Exchange RBAC, and managed connector authority. Separate
deployment and consent operators from runtime identities. Never include tenant
IDs, credentials, object IDs, tokens, or real environment values.

Use `code` for a requirement evidenced by current configuration or hooks,
`documented` for an explicit requirement in project documentation, and
`proposed` for a design awaiting implementation. These states do not claim
least privilege, valid consent, or live endpoint success. Pin repository evidence
with SHA-256 so changed sources appear as review findings. Do not refresh the
hash without reviewing the associated permissions and conditions.

Mark inventory coverage `partial` and describe every known gap. An empty
requirements array with partial coverage means unknown, not permission-free.
Use `complete` only after checking all identities, phases, feature combinations,
Azure scopes, non-Graph resources, connector consent, and cleanup. Complete
inventories must have no gaps.

Feature selection is explicit: default requirements are included automatically;
`-Feature solution-id:feature-id` enables an optional set and `-ExcludeFeature`
disables a default set. Document mutually exclusive configurations in gaps or
feature rationale until their combinations are fully reviewed. `-IncludeOptional`
shows the union of all recorded configurations, not a recommended grant bundle.

Comparison uses exact `(resource, kind, permission, scope)` tuples. A delegated
scope never satisfies an application role. Different API resources or scopes
never overlap. Read and write permissions are not collapsed or assumed to imply
one another. Azure scope labels describe deployment patterns; they do not show
that access to one deployed resource grants access to another.

The canonical registry `portfolio/permission-solutions.json` maps solution IDs
to local manifests. It includes active solutions, staged designs, and explicitly
marked legacy/template entries. Preserve legacy sources; inventory them without
making them the authoring source for active standalone projects.

Review permission changes alongside API/feature changes. Report the old set,
new set, exact additions, principal, phase, reason, and expanded scope before a
grant. A shared host must be assessed against the union of **runtime** requirements
for selected features and principals; bootstrap permissions must not migrate to
its runtime identity. Keep Azure deployment authority, Graph consent, and
feature-operation authority as separate prerequisites.
