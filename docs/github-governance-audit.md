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

## App configuration

Create a private personal-account App named `azd-governance-audit` with:

- Homepage: `https://github.com/nathanmcnulty/azd-reference`.
- No callback URL, user authorization flow, webhook, or subscribed events.
- Repository permissions only:
  - `Administration: read` — required for Actions settings, rulesets, and
    other repository governance settings.
  - `Contents: read` — required to inspect repository trees and workflow files.
  - `Metadata: read` — GitHub requires this and grants it automatically.
- Install only on the repositories in the governance registry, currently 22
  repositories including the private `azd-entra-iga` repository. Do not select
  all repositories.

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
workflow succeeds, and only then revoke the old key. If the App or key is
compromised, revoke the affected key, remove the App installation from the
selected repositories, replace the secret, and review the repository
security/audit logs before reinstalling it.

The App secret is used only by the scheduled/manual audit job on `main`. GitHub
enforces the environment's branch policy before releasing environment secrets;
the workflow also has an in-file default-branch guard. Do not add pull-request
triggers or make the private key available to validation jobs that execute
consumer-controlled code. The audit's `GITHUB_TOKEN` remains read-only and
checkout credentials are not persisted.

## References

- [Deciding when to build a GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/deciding-when-to-build-a-github-app)
- [Choosing permissions for a GitHub App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app)
- [Generating an installation access token](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app)
- [`actions/create-github-app-token`](https://github.com/actions/create-github-app-token/tree/bcd2ba49218906704ab6c1aa796996da409d3eb1)
