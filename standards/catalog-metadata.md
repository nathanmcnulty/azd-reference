# Solution catalog metadata standard

`.azd/catalog.json` is optional, solution-owned descriptive metadata for
`azd-website` and other discovery surfaces. It is display-only: it must not be
used as deployment configuration, a permissions manifest, a GUI deployment
contract, or a substitute for the solution README and documentation.

The machine-readable contract is
[`schemas/catalog-metadata.schema.json`](../schemas/catalog-metadata.schema.json).
It intentionally contains only fields that the current website catalog can
consume. Unknown properties are rejected so that an agent cannot silently add
metadata that the site ignores.

## Where metadata belongs

Create the file at the solution root:

```text
.azd/catalog.json
```

Commit it with the solution. Keep facts about the solution in this file and
keep site-only editorial decisions in the website repository's
`catalog/overrides.json`. The website may infer missing values from GitHub and
the repository description, but inferred copy should be treated as a fallback,
not as a reason to skip useful repository-owned metadata.

Do not store these values in the catalog file:

- repository URLs, stars, languages, update timestamps, or generated IDs;
- tenant IDs, subscription IDs, secrets, tokens, callback URLs, or personal
  filesystem paths;
- permissions, prerequisites, configuration fields, cleanup behavior, or
  deployment modes that belong in `README.md`, `docs/`, or `azd-gui.json`;
- implementation inventory such as every Bicep module, PowerShell script, or
  runtime dependency.

The distinction between the display catalog and the GUI deployment contract is
defined in [`gui-template-contract.md`](gui-template-contract.md).

## GitHub fallback metadata

Keep the GitHub repository description and topics useful even when the catalog
file is present. They support repository search and are the website's fallback
when a catalog field is omitted.

- Use a single plain-language sentence for the repository description and keep
  it consistent with `summary`.
- Use lowercase, hyphenated topic names that correspond to the catalog's
  user-facing tags, such as `microsoft-entra-id` or `conditional-access`.
- Do not use generic or implementation-only topics merely to increase the tag
  count. Do not maintain contradictory descriptions in GitHub and the catalog.

The committed catalog remains the preferred source for curated website copy;
GitHub metadata should not become a second, conflicting authoring system.

## Writing rules

Write for someone deciding whether to open the repository. The website copy
should be short, friendly, concrete, and understandable without reading the
source code.

- Prefer active verbs such as **Set up**, **Review**, **Notify**, **Protect**,
  and **Deploy**.
- Describe the user-visible outcome and the main Azure or Microsoft 365
  scenario. Do not describe the repository's internal architecture.
- Use normal product names on first mention. Avoid unexplained internal names,
  dense acronyms, and marketing claims.
- Only claim behavior that is implemented, documented, and covered by the
  solution's validation. Be careful with words such as *secure*,
  *production-ready*, *automatic*, *zero trust*, and *secret-free*.
- Put permissions, consent, costs, tenant scope, destructive actions, version
  requirements, and cleanup instructions in the repository documentation.

The catalog is intentionally less technical than the README. A reader should
be able to understand the card and decide whether to continue in a few seconds;
the repository should answer the detailed “how” and “what could this change?”
questions.

## Field guidance

All fields are optional. Omit a field when its value cannot be verified instead
of guessing. The following targets are writing guidance; the JSON Schema checks
shape and types, while review checks clarity and accuracy.

The validator also applies conservative processing limits: the file must be an
ordinary UTF-8 Git blob no larger than 32 KiB, JSON nesting may not exceed 16
levels, strings may not exceed 4,096 characters, and array fields may contain
at most 32 items. JSON comments, trailing commas, duplicate property names,
symlinks, submodules, and Git LFS pointers are rejected. These limits keep
validation deterministic and prevent display metadata from becoming a payload
or execution surface.

| Field | Guidance |
| --- | --- |
| `title` | Use a human title of roughly two to six words. Make it specific enough to distinguish the solution without repeating the repository slug. |
| `summary` | Use one friendly sentence, ideally about 12–24 words and no more than about 160 characters. State the outcome and primary scenario; do not put prerequisites or a setup checklist here. |
| `tags` | Use about two to five durable, user-facing discovery terms. Prefer Microsoft products, workloads, and security or operations concepts. Do not use generic `Azure` or `azd`, and do not add stack labels such as `.NET`, `Bicep`, or `App Service` merely because the repository uses them. Include a platform tag only when it is a meaningful user choice or search intent. |
| `highlights` | Use two to four short, parallel phrases. Keep each one to a single idea and roughly 90 characters or fewer. Describe useful outcomes, safe defaults, or meaningful choices; leave detailed caveats to the README. |
| `featured` | Use `true` only for an intentional website editorial choice. It is not a maturity, security, or support guarantee. Prefer `false` or omission for normal templates. |
| `solutionCount` | Count actual user-selectable solution variants or hosting paths. Do not count scripts, components, optional flags, notification transports, or individual features. Use `1` when the user receives one solution. |
| `quickstartCommands` | Include the shortest tested path from a clean shell to the first supported step. Usually this is `azd init` followed by `azd up`; use clone, `cd`, environment, or custom deployment commands when the repository really requires them. Keep it to a few copyable command lines and never include secrets, personal paths, or unverified placeholders. |

`quickstartCommands` are documentation. The website and GUI do not execute them.
They must agree with the repository README, `azure.yaml`, hooks, and any custom
deployment script. If the first-run path needs explanation or a required
permission cannot be represented safely in a command, keep that explanation in
the README and link readers there rather than making the catalog longer.
The generated guide currently renders these lines in a PowerShell code block,
so keep them PowerShell-compatible and put shell-specific alternatives in the
repository documentation.

## Example

This is the intended level of detail:

```json
{
  "title": "Device lifecycle notifications",
  "summary": "Notify users and administrators about Microsoft Entra and Intune device changes.",
  "tags": [
    "Microsoft Entra ID",
    "Microsoft Intune",
    "Device Management"
  ],
  "highlights": [
    "Supports Teams and email delivery",
    "Starts with a test group and paused collection",
    "Only notifies—it never changes device state"
  ],
  "featured": false,
  "solutionCount": 3,
  "quickstartCommands": [
    "azd init -t nathanmcnulty/azd-device-notifications",
    "azd up"
  ]
}
```

The example gives a visitor a useful orientation without attempting to explain
identity permissions, configuration, scheduling, or operational cleanup.

## Instructions for repository-authoring agents

When creating or updating a public `azd` solution:

1. Read the root `azure.yaml`, README, deployment scripts, hooks, and relevant
   validation before writing metadata. Identify the simplest supported path and
   the actual user-visible result.
2. Add or update `.azd/catalog.json` only after the commands and claims have
   been checked against that source. Do not invent a quick start because a
   command looks conventional.
3. Keep the summary to one plain-language sentence. Use tags for discovery and
   highlights for a few outcomes; move technical setup, permissions, risk,
   costs, and cleanup to the repository docs.
4. Omit optional fields that are uncertain. In particular, do not inflate
   `solutionCount`, mark a template `featured`, or promise security properties
   without evidence.
5. Validate the JSON against the catalog schema before committing. If the
   website checkout is available, also run its catalog validator; otherwise use
   `Test-Json` with this repository's schema.
6. Re-read the rendered wording as a card and as a short guide page. Remove
   repeated phrases, implementation details, and anything that requires the
   reader to know the repository's internal vocabulary.

A compact instruction that can be included in an agent task is:

> Add root `.azd/catalog.json` using the azd catalog metadata schema. First
> verify the supported quick-start path from `azure.yaml` and the README. Write
> a short friendly summary, two to five user-facing tags, and only a few
> evidence-based highlights. Keep technical setup, permissions, costs, risks,
> and cleanup in the repository documentation. Do not add secrets, generated
> GitHub fields, stack labels, or unsupported properties. Validate the file
> before committing.

## Evolution and review

Adding a catalog field is a cross-repository contract change. Update the
reference schema, website validator, generated guide/card rendering, examples,
and tests together. Do not add a custom property to a solution and assume the
website will preserve it.

When a solution's behavior changes, review its catalog copy in the same change.
Repository-owned metadata should describe facts; use a website override only for
site-specific curation or a temporary editorial correction. Remove an override
when the fact has been corrected at the source.
