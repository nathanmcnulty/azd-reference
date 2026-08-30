# Repository baseline standard

[`portfolio/repository-baseline.json`](../portfolio/repository-baseline.json) is
the machine-readable minimum for independently supported azd solutions. The
baseline audits repository and solution roots separately so a solution inside an
incubation repository does not pretend to own repository-level workflows.

The baseline is an audit contract, not an overlay. README content, security
contacts, dependency ecosystems, validation commands, and workflow jobs remain
repository-owned. Do not copy them blindly from another solution.

External GitHub Actions use full commit SHAs with readable version comments.
Workflow permissions default to `contents: read`, and dependency updates are
grouped and bounded. The status tool enforces these portable lexical controls;
every Dependabot `updates` entry must independently declare a group and a
positive open-pull-request limit. Repository-owned validation remains responsible
for deeper workflow semantics. A repository may add stricter controls.

`.azd/catalog.json` is recommended while older solutions are migrated. Once the
catalog contract is proven across the portfolio it can become required in a new
baseline version.
