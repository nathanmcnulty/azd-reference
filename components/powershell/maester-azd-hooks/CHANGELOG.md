# Changelog

## 0.1.6 - 2026-10-07

- Validate the optional Web App security group Object ID as a non-empty GUID before persisting wizard settings.
- Give interactive users group lookup and Web App skip guidance while keeping non-interactive failures explicit.

## 0.1.5 - 2026-09-20

- Avoid passing mutually exclusive tenant and subscription selectors to Azure CLI token acquisition.

## 0.1.4 - 2026-09-20

- Allow Azure CLI access-token requests to target an explicit subscription.

## 0.1.3 - 2026-09-20

- Retry Azure DevOps service-connection deletion while pipeline cleanup is asynchronous.

## 0.1.2 - 2026-09-20

- Preserve pre-existing Azure DevOps repositories during environment teardown.

## 0.1.1 - 2026-09-20

- Retry managed identity principal discovery while ARM identity propagation completes.

## 0.1.0 - 2026-09-19

- Initial pilot release extracted from the azd-maester shared hook and permission helpers.
