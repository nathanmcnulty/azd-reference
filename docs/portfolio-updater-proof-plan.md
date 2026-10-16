# Bounded portfolio updater proof plan

This is a plan, not evidence that the GitHub App publishing path has run.
Existing discovery runs and skipped preparation/publication do not prove App
configuration, branch creation or draft-PR publication.

Use the existing `portfolio-updates.yml`, consumer registry and configured updater
App. Do not create credentials, read private-key values, expand App installation
scope, change App permissions or bypass release-integrity checks for this proof.
The Automation runbook lifecycle candidate is deliberately not a proof target:
it has no reviewed immutable release or consumer adoption approval yet.

## Select one legitimate update

1. Re-read current default branches, approved desiredVersion values and component
   release tags/attestations. Run the existing read-only status/candidate tooling.
2. Choose exactly one registered personal consumer with a genuinely outstanding,
   explicitly approved component version, a valid immutable release, clean
   managed files, and a repository-owned offline validation entry point.
3. Confirm no other candidate would be selected and no equivalent draft PR is
   already open. The current manual workflow has no consumer selector: do not
   dispatch it when it would update other consumers. Do not fabricate drift,
   downgrade a lock, change desiredVersion, or delete an existing PR to force work.
4. If no eligible single update exists, report that blocker and wait for a real
   reviewed adoption packet. A successful empty discovery is not end-to-end proof.

## Observe the existing chain

For the separately authorized single-target run, record the exact reference and
consumer heads, component tag/revision, workflow run and environment approval
(if configured). Require preparation and validation to execute without a write
credential. Then observe the existing selected-repository App-token action and
publisher; do not extract or persist the token.

Verify the remote branch is the validated commit, the draft PR author is the
configured App, the base repository/branch is correct, and the diff contains only
managed component paths plus lock/provenance/baseline changes already expected by
the approved packet. Check the consumer's CI for that exact head and retain the
run, draft PR and evidence links. Do not approve, merge or deploy it.

Run read-only candidate discovery again: the exact existing draft should be
excluded, demonstrating duplicate prevention without another write attempt.
Stop once this evidence is established or an actual permission, environment,
release, drift or validation blocker requires a separate decision. An App setup
failure is not authority to replace credentials or broaden access.

## Scope notes

The updater reconciles approved desiredVersion values; it is not a latest-version
selector. Built-in Dependabot handles its configured package/action ecosystems,
not these vendored component contracts. Component source, release, consumer lock,
registry desiredVersion, runtime deployment and service acceptance remain distinct.
