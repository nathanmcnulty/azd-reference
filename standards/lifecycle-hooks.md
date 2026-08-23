# Lifecycle hook standard

Azure Developer CLI supports a single hook object or an ordered array of hooks
for each lifecycle event. Use the narrowest event that has the state a script
needs.

| Hook | Portfolio use |
| --- | --- |
| `preprovision` | Validate local configuration and establish one shared authentication context when tenant reconciliation requires it. |
| `postprovision` | Reconcile tenant configuration, publish workloads implemented outside azd services, and validate infrastructure-only solutions. |
| `postdeploy` | Validate solutions whose azd-managed service code must be running. |
| `predown` | Apply explicit cleanup guards and remove only solution-owned external state. |

Rules:

- Use an array when sequencing more than one concern; do not create an umbrella
  script merely to hide supported hook ordering.
- Put read-only `Test-Deployment.ps1` last in the relevant event.
- Set `continueOnError: false` for security, reconciliation, and validation hooks.
- Set `interactive: true` only when a normal broker/browser prompt may genuinely
  be required.
- Never place synthetic delivery under an automatic hook.
- Do not rely solely on `postup`; users may run lifecycle commands separately.
- Aggregate Microsoft Graph scopes before one normal connection. Individual
  modules must not reconnect independently.
- Hooks must not disconnect a cached user context they did not create.
