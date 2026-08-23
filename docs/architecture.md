# Portfolio architecture

## Repository roles

| Repository type | Responsibility |
| --- | --- |
| `azd-work-in-progress` | Incubate new solutions and solution-specific experiments. |
| `azd-reference` | Own standards, schemas, canonical components, and update tooling. |
| Independent `azd-*` repository | Ship one independently supported, self-contained solution. |
| `azd-gui` | Discover, configure, and explain templates and component provenance. |

## Distribution model

Components are vendored, not dynamically imported:

```text
azd-reference component + version
              |
              | explicit synchronization
              v
consumer files + azd-components.lock.json
              |
              | no reference-repository access
              v
       azd init / provision / deploy
```

This deliberately duplicates small source files. The duplication is controlled
by versioning, hashes, drift checks, and update pull requests. It avoids private
registry credentials, network availability, and mutable upstream code becoming
deployment prerequisites.

## Ownership boundary

Each component manifest lists only files it owns. Consumers extend behavior in
separate project-owned wrappers, configuration, or callbacks. A component update
must not rewrite an unlisted file.

For deployment validation, the shared component owns validation primitives. The
consumer owns `scripts/Test-Deployment.ps1` and its check definitions because the
actual checks and required permissions are solution-specific.

## Release sequence

1. Change and test a component in this repository.
2. Assign a semantic version in `component.json`.
3. Pilot synchronization into selected consumer branches.
4. Validate the consumer locally and in its normal CI.
5. Commit the copied files and lock update together.
6. Roll the same version to other consumers through reviewable pull requests.

Repository tags identify reviewed source snapshots. Component versions describe
compatibility independently and the lock always records a full source commit.

## Deferred control plane

Cross-repository update pull requests will eventually use a narrowly scoped
GitHub App. The MVP performs local, explicit synchronization only. It does not
copy workflows, approve changes, or merge updates.
