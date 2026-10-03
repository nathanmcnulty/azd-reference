#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]] $Paths,
    [switch] $ReadyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validatorPath = Join-Path $PSScriptRoot 'Test-AzdBacklog.ps1'
$null = & $validatorPath -Paths $Paths

$rows = foreach ($path in $Paths) {
    $fullPath = [IO.Path]::GetFullPath($path)
    $backlog = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json -Depth 100
    foreach ($item in @($backlog.items)) {
        if ($ReadyOnly -and (
                [string] $item.status -ne 'ready' -or
                [string] $item.authorization -ne 'local-only'
            )) {
            continue
        }

        [pscustomobject]@{
            repository = [string] $backlog.repository
            id = [string] $item.id
            title = [string] $item.title
            kind = [string] $item.kind
            priority = [string] $item.priority
            status = [string] $item.status
            wave = [int] $item.wave
            authorization = [string] $item.authorization
            components = @($item.components)
            dependencies = @($item.dependencies)
            sourceRevision = [string] $backlog.sourceRevision
            capturedAt = [string] $backlog.capturedAt
            path = $fullPath
            blocker = if ($null -eq $item.blocker) { $null } else { [string] $item.blocker }
        }
    }
}

$rows | Sort-Object wave, priority, repository, id
