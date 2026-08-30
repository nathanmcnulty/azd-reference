# Repository layout standard

An independently supported solution should use the following baseline where the
folders apply:

```text
.github/workflows/validate.yml
azure.yaml
infra/
scripts/
  Test-Deployment.ps1
  shared/
src/
tests/
docs/
azd-components.lock.json
LICENSE
README.md
SECURITY.md
```

Requirements:

- `azure.yaml` is at the template root.
- Generated infrastructure output is either reproducibly committed and checked,
  or consistently excluded; a repository must not alternate between policies.
- Scripts fail closed on missing required context.
- Tenant cleanup is explicit and solution-owned. Shared components must not infer
  resources to delete.
- Optional features expose deployment outputs and validation state separately.
- Public templates contain everything required to initialize and deploy them.
- Managed files use hashes of the exact committed source blobs. Consumer
  `.gitattributes` must enforce LF for `**/vendor/**` and
  `azd-components.lock.json`. A stale CRLF working representation is accepted
  only when Git explicitly reports `text eol=lf` for that exact target.
