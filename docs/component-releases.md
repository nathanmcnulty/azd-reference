# Component release tags

Component releases are immutable, signed annotated Git tags. A version is ready
for portfolio consumption only after the exact signed tag, reviewed commit and
supplied source bundle pass `Test-AzdReleaseIntegrity.ps1 -AcceptComponentRelease`.
A successful `Attest component release bundle` workflow alone is insufficient.
Source-only pilots, reviewed commits and passing tests are not component releases.

The tag name is:

```text
component/<component-id>/v<semantic-version>
```

An annotated but unsigned tag is not a release. Never move, replace, or delete a
published component tag to repair signing or attestation. Correct the cause,
prepare a new semantic patch version, and publish a new tag.

## Maintainer preflight

Start from a clean checkout of the reviewed merge on the default branch. Replace
the example values before running any command:

```powershell
$repository = 'nathanmcnulty/azd-reference'
$component = 'deployment-validation'
$version = '1.1.1'
$releaseCommit = '<full merged commit SHA>'
$tag = "component/$component/v$version"
$manifestPath = "components/powershell/$component/component.json"

git fetch origin main --tags
if ($LASTEXITCODE -ne 0) { throw 'Failed to refresh origin/main and tags.' }
git merge-base --is-ancestor $releaseCommit origin/main
if ($LASTEXITCODE -ne 0) { throw 'Release commit is not on origin/main.' }

$remoteTag = git ls-remote --tags origin "refs/tags/$tag"
if ($LASTEXITCODE -ne 0) { throw 'Failed to query remote tags.' }
if ($remoteTag) { throw "Tag already exists on origin: $tag" }
git show-ref --verify --quiet "refs/tags/$tag"
if ($LASTEXITCODE -eq 0) { throw "Tag already exists locally: $tag" }
if ($LASTEXITCODE -ne 1) { throw 'Failed to query local tags.' }

$manifest = (git show "${releaseCommit}:$manifestPath") | ConvertFrom-Json
if ($manifest.id -ne $component -or $manifest.version -ne $version) {
  throw 'Component manifest does not match the proposed tag.'
}

$governance = ./tooling/Get-AzdGitHubGovernanceStatus.ps1 `
  -Repository $repository `
  -AsJson | ConvertFrom-Json
$tagFindings = @($governance.findings | Where-Object { $_ -match '^releaseTag' })
if ($governance.state -eq 'unavailable' -or $tagFindings.Count -gt 0) {
  throw "Active immutable release-tag rules were not verified: $tagFindings"
}
```

Use the component's actual manifest path when it is not under
`components/powershell`. Review the component diff, changelog, lifecycle status,
and repository validation for the exact merge. Confirm that no later default-
branch change must be part of the release.

The maintainer must have a Git signing key configured locally and recognizable by
GitHub for the same account that will push the tag. GPG and SSH public keys must
be registered with that account; S/MIME must chain to a root GitHub trusts.
Confirm the key, signing format, committer identity, and GitHub verification setup
before creating the tag:

```powershell
git config --get user.signingkey
git config --get gpg.format
git var GIT_COMMITTER_IDENT
```

An empty signing key is a stop condition. Git supports GPG, SSH, and S/MIME tag
signatures; use the repository maintainer's established format and GitHub's
current [signature-verification guidance](https://docs.github.com/authentication/managing-commit-signature-verification/about-commit-signature-verification).
Do not generate or register a new key as an incidental part of a release.

## Create and verify locally

Create the tag only after the preflight succeeds:

```powershell
git tag -s $tag $releaseCommit -m "$component $version"
if ($LASTEXITCODE -ne 0) { throw "Failed to create signed tag: $tag" }
git verify-tag $tag
if ($LASTEXITCODE -ne 0) { throw "Local signature verification failed: $tag" }

$resolvedCommit = git rev-list -n 1 $tag
if ($LASTEXITCODE -ne 0 -or $resolvedCommit -notmatch '^[0-9a-f]{40}$') {
  throw 'Failed to resolve the local tag to one full commit SHA.'
}
if ($resolvedCommit -ne $releaseCommit) {
  throw "Tag resolves to $resolvedCommit instead of $releaseCommit."
}
```

If local verification fails, delete only the unpublished local tag, repair the
signing configuration, and repeat the preflight. Do not push an unverifiable tag.

## Push and verify on GitHub

Push one exact tag, without a force option:

```powershell
git push origin "refs/tags/$tag:refs/tags/$tag"
if ($LASTEXITCODE -ne 0) { throw "Tag push failed: $tag" }
```

The push alone does not establish release acceptance. The shared gate below
checks that the GitHub reference is the same annotated tag object as the local
tag; its internal name and commit are exact, and GitHub's signature verification
is Boolean `true`. The producer also binds that verified commit to the local
tag, checkout and event SHA before archiving the verified identity.

If GitHub does not verify a published tag, leave it immutable. Diagnose the
signing identity and use a new patch version after review.

## Confirm attestation

The tag push starts `.github/workflows/release-attestation.yml`. Allow at most one
minute for Actions to index the exact push run, then record its ID, wait for
success, and download only its expected source bundle:

```powershell
$run = $null
for ($attempt = 1; $attempt -le 12 -and -not $run; $attempt++) {
  $runs = gh run list --repo $repository `
    --workflow release-attestation.yml `
    --branch $tag `
    --commit $releaseCommit `
    --event push `
    --limit 5 `
    --json databaseId,headBranch,headSha,event,status,conclusion,url |
    ConvertFrom-Json
  if ($LASTEXITCODE -ne 0) { throw 'Failed to query attestation workflow runs.' }
  $run = $runs |
    Where-Object {
      $_.headBranch -eq $tag -and
      $_.headSha -eq $releaseCommit -and
      $_.event -eq 'push'
    } |
    Select-Object -First 1
  if (-not $run -and $attempt -lt 12) { Start-Sleep -Seconds 5 }
}

if (-not $run) { throw "No attestation run found for $tag." }
gh run watch $run.databaseId --repo $repository --exit-status
if ($LASTEXITCODE -ne 0) { throw "Attestation workflow failed for $tag." }

$repositoryName = ($repository -split '/')[-1]
$safeTag = $tag -replace '/', '-'
$artifactName = "$repositoryName-$safeTag"
$artifactDirectory = Join-Path $env:TEMP "azd-reference-attestation-$($run.databaseId)"
if (Test-Path $artifactDirectory) {
  throw "Artifact directory already exists: $artifactDirectory"
}
gh run download $run.databaseId --repo $repository `
  --name $artifactName `
  --dir $artifactDirectory
if ($LASTEXITCODE -ne 0) { throw 'Failed to download the expected source bundle.' }
$bundlePath = Join-Path $artifactDirectory "$artifactName.tar.gz"
if (-not (Test-Path -LiteralPath $bundlePath -PathType Leaf)) {
  throw "Expected source bundle was not downloaded: $bundlePath"
}
$accepted = ./tooling/Test-AzdReleaseIntegrity.ps1 `
  -AcceptComponentRelease `
  -ExpectedRepository $repository `
  -ExpectedTag $tag `
  -ExpectedCommit $releaseCommit `
  -BundlePath $bundlePath
$accepted
```

The gate reads the component manifest from the exact tagged commit and requires
its ID/version to match the validated tag. It verifies the supplied bundle with
`gh attestation verify` constrained to `nathanmcnulty/azd-reference`, that exact
source tag and full commit, `.github/workflows/release-attestation.yml` at that
same signer commit, SLSA provenance v1, the GitHub Actions OIDC issuer, and
`--deny-self-hosted-runners`. The host is explicitly `github.com`. It records the
bundle's SHA-256 and checks that the
bytes did not change during verification. Missing or expired artifacts,
unavailable/unsupported verification, malformed evidence, mismatched identities
and verification failures all stop acceptance; there is no workflow-success
fallback. Use a GitHub CLI version supporting these
[verification options](https://cli.github.com/manual/gh_attestation_verify).

Record the returned tag, `tagObject`, `revision`, `bundleSha256` and
`attestationVerified` alongside the workflow run URL. Only then prepare consumer
locks and their normal review and validation pull requests.

For multiple components at the same merge, complete this verification for the
first tag before pushing the next. Each tag has its own immutable identity,
workflow run, bundle, and attestation result.

## Reuse at publication and adoption boundaries

Run the same explicit gate after a publisher obtains the release bundle and
again before an adoption caller uses that release. Supply the already reviewed
repository/tag/full commit and an already available bundle; the verifier does
not discover or download releases. `-RepositoryRoot` may point to a local
reference checkout containing the expected tag and commit. Acceptance is
currently intentionally scoped to `nathanmcnulty/azd-reference` on `github.com`.

Use the returned immutable `revision` for subsequent `Sync-AzdComponent.ps1
-Revision` calls and lock provenance. Do not resolve `-Version` or the tag again
after acceptance: a later ref lookup would reopen a check/use gap. Keep the
reviewed expected commit fixed across publication and adoption. The result is a
single invocation's evidence, not a reusable authorization or a new receipt
format. Its `state: accepted` is explicitly scoped by `evidenceScope` to signed-
tag and attested-bundle identity, not acceptance of every release-policy rule.
Existing synchronization raw-blob hashes and drift checks still apply.

This opt-in gate does not yet change the scheduled updater, publication command
or consumer synchronization callers. Their download/authentication/publication
boundary must be wired and reviewed separately. It also does not prove active
immutable-tag ruleset protection or replace the maintainer's governance,
default-branch ancestry and change-review preflight above. Source-only pilots
remain unreleased until the actual release evidence passes.

Without `-AcceptComponentRelease`, the tool retains its offline static audit.
The existing `-Tag` option adds only local annotated-tag/signature checking; it
is not component-release acceptance. The explicit acceptance mode always throws
on failure and cannot be weakened with `-FailOnFindings` omitted.
