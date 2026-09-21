# Component release tags

Component releases are immutable, signed annotated Git tags. A version is ready
for portfolio consumption only after GitHub verifies the tag signature and the
`Attest component release bundle` workflow succeeds for that exact tag.

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

Immediately verify the remote object. A release tag must resolve first to a Git
tag object, and GitHub must mark that tag object's signature as verified:

```powershell
$tagRef = gh api "repos/$repository/git/ref/tags/$tag" | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Failed to read the remote tag reference.' }
if ($tagRef.object.type -ne 'tag') {
  throw 'Remote release is not an annotated tag.'
}

$tagObject = gh api "repos/$repository/git/tags/$($tagRef.object.sha)" |
  ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Failed to read the signed tag object.' }
if (-not $tagObject.verification.verified) {
  throw "GitHub did not verify $tag. Do not consume this version."
}
if ($tagObject.tag -ne $tag) {
  throw 'Signed tag object has an unexpected internal tag name.'
}
if ($tagObject.object.sha -ne $releaseCommit) {
  throw 'Verified tag does not point to the reviewed release commit.'
}
```

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
gh attestation verify $bundlePath `
  --repo $repository `
  --signer-workflow "$repository/.github/workflows/release-attestation.yml" `
  --source-ref "refs/tags/$tag" `
  --source-digest $releaseCommit `
  --deny-self-hosted-runners
if ($LASTEXITCODE -ne 0) { throw 'Bundle attestation verification failed.' }
Get-FileHash $bundlePath -Algorithm SHA256
```

Record the tag, tag-object SHA, release commit, workflow run URL, bundle SHA-256,
and attestation verification result. Only then update consumer locks and open
their normal review and validation pull requests.

For multiple components at the same merge, complete this verification for the
first tag before pushing the next. Each tag has its own immutable identity,
workflow run, bundle, and attestation result.
