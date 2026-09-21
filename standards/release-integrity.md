# Release integrity standard

Public `azd` repositories use two complementary release controls:

1. a signed, annotated release tag protected from update and deletion; and
2. a GitHub Actions provenance attestation for the exact source release bundle
   and for every additional artifact the repository publishes.

The migration contract is
[`portfolio/release-integrity.json`](../portfolio/release-integrity.json).
The starter workflow is
[`skeleton/.github/workflows/release-attestation.yml`](../skeleton/.github/workflows/release-attestation.yml).

## Release tag requirements

- Use the repository's registered release-tag namespace. Deployable templates
  normally use `refs/tags/v*`; `azd-reference` uses its registered
  `refs/tags/component/**/*` namespace.
- Create an annotated tag locally and sign the tag with a key GitHub can verify.
  A lightweight tag is not sufficient.
- The tag must point to the exact reviewed commit on the default branch. Do not
  retarget a release tag after publication.
- The active tag ruleset must block both updates and deletion. The tag workflow
  verifies the GitHub tag object's `verification.verified` value before it
  creates or attests a release bundle.

GitHub rulesets protect the tag namespace, while the release workflow verifies
the tag object. This is intentionally two layers: a protected tag cannot be
silently retargeted, and an unsigned or lightweight tag cannot receive the
standard release attestation.

## Artifact requirements

- Every version tag produces a deterministic source-release archive from the
  exact tagged commit. This gives source-only templates a verifiable artifact,
  even when they do not compile a binary.
- Every binary, container, package, or other published build artifact receives
  its own provenance attestation. Do not attest a checksum or an unrelated
  directory in place of the artifact.
- Generate the attestation with the pinned `actions/attest` action and only the
  permissions it needs: `contents: read`, `id-token: write`, and
  `attestations: write`. Add `packages: write` only when publishing a
  container, and add linked-artifact metadata permissions only when that
  feature is deliberately used.
- Generate an SBOM when the repository produces a built artifact; an SBOM
  attestation is recommended alongside the artifact provenance.
- Keep the release workflow read-only with respect to repository contents. It
  must not mint a long-lived credential or embed a signing key.

The starter workflow uses GitHub's SLSA provenance predicate and full commit
SHAs for every action. Consumers can verify a downloaded bundle with
`gh attestation verify <path> -R OWNER/REPOSITORY`.

## Migration sequence

1. Add the standard `SECURITY.md` sections.
2. Add the pinned release-attestation workflow and verify it locally.
3. Create the next release as a signed annotated tag from the reviewed default
   branch.
4. Confirm the uploaded source bundle has a successful attestation before
   treating the release as consumable.
5. Add attestation verification to any future automated consumer or promotion
   workflow.

The contract is marked `migration` until each repository has its workflow and
the next release has produced verifiable evidence. This keeps existing branch
and dependency gates fail-closed while the release controls are rolled out.

See GitHub's documentation for [ruleset signing and tag protections](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets) and [artifact attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations).
