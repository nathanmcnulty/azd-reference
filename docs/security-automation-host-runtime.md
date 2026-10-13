# Security automation host runtime

The supported development and validation baseline is PowerShell 7.6 or newer.
The `security-automation-host@0.1.5` source-only pilot selects `7.6` in the
Functions Flex `functionAppConfig.runtime` and in the Automation runtime
environment used by Automation and Logic App modes. Runbooks bind to
`SecurityPowerShell76`; updating source does not delete a retained older
environment or pause an existing deployed job.

Microsoft documents PowerShell 7.6 as generally available for
[Functions Flex and the other listed hosting plans](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-powershell#powershell-versions).
The worker uses .NET 10. Microsoft also documents 7.6 support for cloud and
hybrid jobs through the [Automation runtime environment experience](https://learn.microsoft.com/en-us/azure/automation/automation-runbook-types#powershell-runbooks).
These product contracts were checked on 13 October 2026. They establish
platform support; startup, job execution and selected-region availability
still need deployment evidence for the exact source and package.

Compiled-template checks verify both runtime selections and the runbook's
environment binding, alongside the existing host role scopes and disabled
schedule conditions. The default `none` mode remains compute-free. No Graph
permission, collector assignment or policy write is introduced by this update.
Immutable consumer adoption and source/package review remain separate from
live Function, Automation, Logic App, identity, report, pause and teardown proof.
Earlier 7.4 source and validation records remain historical evidence; no
compatibility work or test run on that version is part of this update.
