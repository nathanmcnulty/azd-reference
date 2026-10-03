# GitHub governance audit runbook

The scheduled audit compares live GitHub settings and workflow files with the
contracts in `portfolio/github-governance.json` and
`portfolio/github-governance-repositories.json`. It is read-only and runs
weekly on `main` or by manual dispatch from `main`.

## Credential decision

Use a dedicated GitHub App for this recurring cross-repository integration.
A fine-grained PAT would be simpler and is a viable choice for a single owner,
but it would remain a user credential; any chosen expiration requires manual
rotation. This audit is a long-lived scheduled integration with repository
administration read access, so the App's independent identity and short-lived
installation tokens justify the small extra setup. Keep it separate from
`nathanmcnulty-azd-updater`: that App can mint write-capable tokens for its
publishing workflow and must not gain audit permissions across the portfolio.

### Alternatives checked

The credential choice was reviewed against GitHub's documented authentication
options on 2026-10-02 for a personal account with one permanent maintainer:

| Option | Fit for this audit |
| --- | --- |
| Built-in `GITHUB_TOKEN` | Automatically managed, but limited to its own repository and cannot request the repository `Administration` permission needed by the settings APIs. Moving the audit into each repository does not solve that permission gap. |
| Public unauthenticated API reads | Useful for public manifests and metadata, but cannot provide the administrator settings or private-repository coverage this audit requires. |
| Fine-grained PAT | Supports the required read permissions with less initial setup, but remains a user credential whose expiration and replacement must be managed. Viable fallback. |
| GitHub App with an environment secret | Separate read-only identity, selected repositories, short-lived installation tokens, and no extra hosting. Preferred for this portfolio. The signing key still needs protection and rotation. |
| OIDC with an external signer or token broker | Can avoid storing the App key in Actions. GitHub's installation-token flow still requires an App-signed JWT; OIDC does not directly replace it. A sign-only Key Vault key offers stronger protection from key extraction, but adds cloud identity, infrastructure, cost, and signing integration to maintain. Reconsider if that infrastructure becomes an established shared service. |
| Manual local audit using `gh` authentication | Avoids a new automation secret, but cannot provide the unattended weekly audit. Useful for diagnosis and independent verification. |

For this small read-only integration, use the dedicated App with an Actions
environment secret. Do not introduce a cloud signing service solely for this
audit. No OAuth client secret is needed because the App does not authorize users.

## App configuration

Create a private personal-account App named `azd-governance-audit` with:

- Homepage: `https://github.com/nathanmcnulty/azd-reference`.
- No callback URL, user authorization flow, webhook, or subscribed events.
- Repository permissions only:
  - `Administration: read` — required for Actions settings, rulesets, and
    other repository governance settings.
  - `Contents: read` — required to inspect repository trees and workflow files.
  - `Metadata: read` — GitHub requires this and grants it automatically.
- Use **Only select repositories** when installing. The owner approved access
  to the current 25 `azd-*` repositories, including the private tools
  `azd-gui`, `azd-website`, and `azd-work-in-progress`. This is an explicit
  selected list, not GitHub's **All repositories** option or automatic access
  to future repositories. The audit token remains limited to the current 22
  registered repositories, including private `azd-entra-iga`.

In `nathanmcnulty/azd-reference`, save:

- Repository variable `AZD_GOVERNANCE_APP_CLIENT_ID` with the App Client ID.
- Environment `github-governance-audit`, restricted to the `main` branch with
  no required reviewer.
- Environment secret `AZD_GOVERNANCE_APP_PRIVATE_KEY` with the generated PEM
  private key.

The workflow derives its token repository list from the checked-out registry,
validates that every entry belongs to `nathanmcnulty`, and requests only
`Administration: read` and `Contents: read`. If a repository is added to the
registry, install the App on that repository as well. Removing a repository
from the registry automatically removes it from the next token's scope; the
App installation can then be narrowed too.

The token-generation action is pinned to full commit
`bcd2ba49218906704ab6c1aa796996da409d3eb1` (`v3.2.0`). Installation tokens
expire after one hour, and the action revokes its token after the job. The App
private key itself does not become short-lived: treat it as a durable secret,
never put it in workflow output or repository files, and rotate it deliberately.

## Key rotation and recovery

To rotate the private key, generate a replacement in the App settings, update
`AZD_GOVERNANCE_APP_PRIVATE_KEY`, manually run the audit on `main`, verify the
token-generation and report-upload steps succeed, inspect the report, and only
then revoke the old key. A run can fail because it correctly found governance
drift; that does not mean the replacement credential failed. If the App or key is
compromised, revoke the affected key, remove the App installation from the
selected repositories, replace the secret, and review the repository
security/audit logs before reinstalling it.

The App secret is used only by the scheduled/manual audit job on `main`. GitHub
enforces the environment's branch policy before releasing environment secrets;
the workflow also has an in-file default-branch guard. Do not add pull-request
triggers or make the private key available to validation jobs that execute
consumer-controlled code. The audit's `GITHUB_TOKEN` remains read-only and
checkout credentials are not persisted.

## Evidence limits

The App checks settings it can read without executing code from other
repositories. GitHub can omit ruleset `bypass_actors` from a read-only response.
In that case the report explicitly records `ownerRecoveryVerification` as
`manual-required` and the job emits a warning. A `current` state means the
observable automated checks passed; it does not certify this separate recovery
control. Using the owner's normal `gh` session, run the same audit and confirm
the registered repositories report `ownerRecoveryVerification: verified`.
This checks the administrator-role bypass rather than the App's own ability
to bypass rules. Do not grant the App write access merely to reveal this field.

The legacy branch-protection check accepts only GitHub's explicit HTTP 404
`Branch not protected` response as absence. Authorization, rate-limit, service,
and unexpected responses produce an unavailable-audit finding.

## References

- [Deciding when to build a GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/deciding-when-to-build-a-github-app)
- [Choosing permissions for a GitHub App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app)
- [Generating an installation access token](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app)
- [`actions/create-github-app-token`](https://github.com/actions/create-github-app-token/tree/bcd2ba49218906704ab6c1aa796996da409d3eb1)
- [Built-in `GITHUB_TOKEN` scope](https://docs.github.com/en/actions/concepts/security/github_token)
- [Available workflow token permissions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions)
- [Actions settings API permissions](https://docs.github.com/en/rest/actions/permissions#get-github-actions-permissions-for-a-repository)
- [OpenID Connect](https://docs.github.com/en/actions/concepts/security/openid-connect)
- [App private-key protection and sign-only key vaults](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/managing-private-keys-for-github-apps)
