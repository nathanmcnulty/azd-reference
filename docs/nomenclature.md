# Portfolio nomenclature

Use these terms consistently when designing and discussing the `azd` portfolio.

| Term | Meaning |
| --- | --- |
| **Solution** | One independently supported, self-contained `azd` template. A solution normally has its own repository and root `azure.yaml`. |
| **Component** | A small, independently versioned set of reusable files governed by `azd-reference` and vendored into one or more solutions. Components are not deployment-time dependencies. |
| **Consumer** | A solution that vendors a component and records its exact version, source commit, file targets, and hashes. |
| **Wrapper** | Solution-owned Bicep, PowerShell, or code that supplies policy and configuration to a component without modifying the vendored files. |
| **Contract** | A versioned interface or schema shared across components and solutions, such as parameters, outputs, notification envelopes, or validation results. |
| **Mode** | A mutually exclusive configuration path inside one solution. A mode is not automatically a separate solution or component. |
| **Vendored copy** | The exact component files checked into a consumer repository so deployment remains self-contained. |
| **Component lock** | `azd-components.lock.json`, which records immutable component provenance and hashes for the vendored copy. |
| **Component release** | An immutable `component/<id>/v<version>` tag that points to reviewed canonical component content. |
| **Portfolio baseline** | A tested combination of component versions and repository standards; it does not force every consumer to deploy every component. |

## Quick test

- If it should be initialized, deployed, operated, and retired independently, it
  is a **solution**.
- If it should be synchronized and upgraded consistently across solutions, it
  is a **component**.
- If it expresses one solution's policy, query, workflow, or user experience
  around a component, it is a **wrapper**.
- If it is only a choice inside one deployment, it is a **mode**.

For example, `flex-scheduled-poller-host` and
`azure-monitor-scheduled-query-notifications` are independently versioned
components. An Entra risk-detection poller and a PIM audit poller remain separate
solution behaviors even when both consume the same Flex host component.
