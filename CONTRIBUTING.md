# Contributing

## Promotion rule

A reusable component should normally have two real consumers or one proven
consumer plus a second reviewed adoption plan. Keep solution-specific code in its
own repository until that evidence exists.

## Component changes

Every component change must:

1. update its `component.json` semantic version;
2. preserve or explicitly version its public contract;
3. add or update focused tests;
4. document migration steps for a breaking change; and
5. prove synchronization and drift detection in a temporary consumer.

After review, create `component/<id>/v<version>` at the reviewed commit. Never
move or reuse a component release tag.

Do not edit generated copies in an example. Change the canonical component and
run the synchronization tooling.

## Pull requests

Use a focused branch. Explain the kept change, its evidence, affected consumers,
and anything deliberately deferred. Never weaken validation merely to make CI
pass.
