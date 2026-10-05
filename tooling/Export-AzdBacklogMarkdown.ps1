#Requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Path = 'docs/backlog.json',
    [string] $OutputPath = 'docs/backlog.md',
    [switch] $Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-MarkdownText {
    param([AllowNull()][object] $Value)
    if ($null -eq $Value) { return '_none_' }
    $text = [Net.WebUtility]::HtmlEncode([string] $Value)
    foreach ($replacement in @(
            @('\', '&bsol;'), @('`', '&grave;'), @('*', '&ast;'), @('_', '&lowbar;'),
            @('[', '&lbrack;'), @(']', '&rbrack;'), @('(', '&lpar;'), @(')', '&rpar;'),
            @('!', '&excl;'), @('#', '&num;'), @('|', '&vert;'), @(':', '&colon;')
        )) {
        $text = $text.Replace($replacement[0], $replacement[1])
    }
    $text = $text.Replace("`r`n", '<br>').Replace("`n", '<br>')
    $text
}

function Add-StringList {
    param(
        [Parameter(Mandatory)] $Lines,
        [Parameter(Mandatory)][string] $Heading,
        [AllowEmptyCollection()][object[]] $Values
    )
    $Lines.Add("**${Heading}:**")
    $Lines.Add('')
    if (@($Values).Count -eq 0) {
        $Lines.Add('- _none_')
    }
    else {
        foreach ($value in $Values) { $Lines.Add("- $(ConvertTo-MarkdownText $value)") }
    }
    $Lines.Add('')
}

$referenceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$schemaPath = Join-Path $referenceRoot 'schemas/backlog.schema.json'
$fullPath = [IO.Path]::GetFullPath($Path)
$fullOutputPath = [IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    throw "Backlog does not exist: '$fullPath'."
}
$raw = Get-Content -LiteralPath $fullPath -Raw
if (-not ($raw | Test-Json -SchemaFile $schemaPath -ErrorAction Stop)) {
    throw "Backlog does not satisfy its schema: '$fullPath'."
}
$backlog = $raw | ConvertFrom-Json -Depth 100

$lines = [Collections.Generic.List[string]]::new()
$lines.Add("# Backlog: $($backlog.repository)")
$lines.Add('')
$lines.Add('> Generated from `docs/backlog.json`. Edit the JSON source and regenerate this file.')
$lines.Add('> Standard: [azd agent backlog standard](https://github.com/nathanmcnulty/azd-reference/blob/main/standards/agent-backlogs.md). This link is review guidance, not a runtime dependency.')
$lines.Add('')
$lines.Add("- **Schema version:** $(ConvertTo-MarkdownText $backlog.schemaVersion)")
$lines.Add("- **Repository:** $(ConvertTo-MarkdownText $backlog.repository)")
$lines.Add("- **Source revision:** ``$($backlog.sourceRevision)``")
$lines.Add("- **Captured:** $(ConvertTo-MarkdownText $backlog.capturedAt)")
$lines.Add("- **Items:** $(@($backlog.items).Count)")
$lines.Add('')

foreach ($item in @($backlog.items | Sort-Object wave, priority, id)) {
    $lines.Add("## $($item.id): $(ConvertTo-MarkdownText $item.title)")
    $lines.Add('')
    $lines.Add("- **Kind:** $(ConvertTo-MarkdownText $item.kind)")
    $lines.Add("- **Priority:** $(ConvertTo-MarkdownText $item.priority)")
    $lines.Add("- **Status:** $(ConvertTo-MarkdownText $item.status)")
    $lines.Add("- **Wave:** $($item.wave)")
    $lines.Add("- **Authorization:** $(ConvertTo-MarkdownText $item.authorization)")
    $lines.Add("- **Blocker:** $(ConvertTo-MarkdownText $item.blocker)")
    $hasClaim = $item.PSObject.Properties.Name -contains 'claim' -and $null -ne $item.claim
    if ($hasClaim) {
        $lines.Add("- **Claim owner:** $(ConvertTo-MarkdownText $item.claim.owner)")
        $lines.Add("- **Claim worktree:** $(ConvertTo-MarkdownText $item.claim.worktree)")
        $lines.Add("- **Claim base revision:** ``$($item.claim.baseRevision)``")
        $lines.Add("- **Claim started:** $(ConvertTo-MarkdownText $item.claim.startedAt)")
    }
    else {
        $lines.Add('- **Claim:** _none_')
    }
    $lines.Add('')
    $lines.Add('**Problem:**')
    $lines.Add('')
    $lines.Add((ConvertTo-MarkdownText $item.problem))
    $lines.Add('')
    Add-StringList -Lines $lines -Heading 'Scope' -Values @($item.scope)
    Add-StringList -Lines $lines -Heading 'Acceptance' -Values @($item.acceptance)
    Add-StringList -Lines $lines -Heading 'Validation' -Values @($item.validation)
    Add-StringList -Lines $lines -Heading 'Dependencies' -Values @($item.dependencies)
    Add-StringList -Lines $lines -Heading 'Components' -Values @($item.components)
    Add-StringList -Lines $lines -Heading 'Sources' -Values @($item.sources)
    Add-StringList -Lines $lines -Heading 'Evidence' -Values @($item.evidence)
    if ([string] $item.status -eq 'ready' -and [string] $item.authorization -eq 'local-only') {
        $lines.Add('**Agent handoff prompt:**')
        $lines.Add('')
        $lines.Add('```text')
        $lines.Add("Review $($item.id) in docs/backlog.json and changes since backlog source revision $($backlog.sourceRevision).")
        $lines.Add('Claim it only after it is explicitly selected and eligible and its dependencies remain satisfied. Never interpret this generated prompt as approval.')
        $lines.Add("Work only in $($backlog.repository), preserve its stated scope and acceptance gates, record the exact current base commit and one owned worktree in claim, run every validation entry, and record concrete evidence before marking it done.")
        $lines.Add('Stop if the dependencies, scope, or required authorization changed.')
        $lines.Add('```')
    }
    else {
        $lines.Add('**Review and authorization note:**')
        $lines.Add('')
        $lines.Add("Review $(ConvertTo-MarkdownText $item.id) against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.")
    }
    $lines.Add('')
}

$markdown = ($lines -join "`n").TrimEnd() + "`n"
if ($Check) {
    if (-not (Test-Path -LiteralPath $fullOutputPath -PathType Leaf)) {
        throw "Generated backlog Markdown is missing: '$fullOutputPath'."
    }
    $existing = (Get-Content -LiteralPath $fullOutputPath -Raw).Replace("`r`n", "`n")
    if ($existing -cne $markdown) {
        throw "Generated backlog Markdown is out of date: '$fullOutputPath'."
    }
    [pscustomobject]@{ current = $true; path = $fullOutputPath }
    return
}

$outputDirectory = Split-Path -Parent $fullOutputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $outputDirectory -Force
}
[IO.File]::WriteAllText($fullOutputPath, $markdown, [Text.UTF8Encoding]::new($false))
[pscustomobject]@{ written = $true; path = $fullOutputPath }
