Set-StrictMode -Version Latest

function ConvertTo-AzdFoundryCanonicalJson {
    param([AllowNull()] $Value, [int] $Depth = 0)
    if ($Depth -gt 32) { throw 'Foundry JSON exceeds the supported nesting depth.' }
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [System.Collections.IDictionary]) {
        $keys = [string[]] @($Value.Keys)
        [Array]::Sort($keys, [StringComparer]::Ordinal)
        $pairs = foreach ($key in $keys) {
            ($key | ConvertTo-Json -Compress) + ':' + (ConvertTo-AzdFoundryCanonicalJson $Value[$key] ($Depth + 1))
        }
        return '{' + ($pairs -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = foreach ($item in $Value) { ConvertTo-AzdFoundryCanonicalJson $item ($Depth + 1) }
        return '[' + ($items -join ',') + ']'
    }
    return ConvertTo-Json -InputObject $Value -Compress -Depth 40
}

function Get-AzdFoundryTextHash {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}

function Resolve-AzdFoundryProjectEndpoint {
    param([Parameter(Mandatory)][string] $ProjectEndpoint)
    # Public Azure only. No userinfo, alternate port, query, escaped path or redirect destination.
    if ($ProjectEndpoint -cnotmatch '^https://[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?\.services\.ai\.azure\.com/api/projects/[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}/?\z') {
        throw 'Expected an exact public Azure Foundry project HTTPS endpoint.'
    }
    return $ProjectEndpoint.TrimEnd('/')
}

function Assert-AzdFoundrySchema {
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Schema)
    $json = ConvertTo-AzdFoundryCanonicalJson $Schema
    if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 32768) { throw 'The output schema exceeds 32768 UTF-8 bytes.' }
    if ($Schema['type'] -cne 'object' -or $Schema['additionalProperties'] -ne $false -or $Schema['properties'] -isnot [System.Collections.IDictionary]) {
        throw 'The output schema must be an object with properties and additionalProperties=false.'
    }
    # Never allow schema validation to fetch another service, including from nested schemas.
    $pending = [System.Collections.Generic.Stack[object]]::new()
    $pending.Push($Schema)
    while ($pending.Count) {
        $node = $pending.Pop()
        if ($node -is [System.Collections.IDictionary]) {
            foreach ($key in $node.Keys) {
                if (($key -eq '$schema' -and [string]$node[$key] -cnotin @('https://json-schema.org/draft/2020-12/schema', 'http://json-schema.org/draft-07/schema#')) -or
                    $key -in @('$id', '$dynamicRef', '$recursiveRef') -or ($key -eq '$ref' -and [string]$node[$key] -notmatch '^#/\$defs/')) {
                    throw 'Output schemas may use only local #/$defs references and no $id or $dynamicRef.'
                }
                if ($null -ne $node[$key]) { $pending.Push($node[$key]) }
            }
        }
        elseif ($node -is [System.Collections.IEnumerable] -and $node -isnot [string]) {
            foreach ($child in $node) { if ($null -ne $child) { $pending.Push($child) } }
        }
    }
}

function New-AzdFoundryAgentDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z')][string] $ModelDeployment,
        [Parameter(Mandatory)][ValidateLength(1, 16384)][string] $Instructions,
        [Parameter(Mandatory)][System.Collections.IDictionary] $OutputSchema,
        [ValidatePattern('^[A-Za-z][A-Za-z0-9_-]{0,63}\z')][string] $SchemaName = 'solution_response'
    )
    Assert-AzdFoundrySchema $OutputSchema
    return [ordered]@{
        kind = 'prompt'; model = $ModelDeployment; instructions = $Instructions
        tools = @(); tool_choice = 'none'
        text = @{ format = @{ type = 'json_schema'; name = $SchemaName; strict = $true; schema = $OutputSchema } }
    }
}

function Assert-AzdFoundryDefinition {
    param([Parameter(Mandatory)][System.Collections.IDictionary] $Definition)
    if (@($Definition.Keys | Where-Object { $_ -cnotin @('kind', 'model', 'instructions', 'tools', 'tool_choice', 'text') }).Count -or
        $Definition['kind'] -cne 'prompt' -or @($Definition['tools']).Count -ne 0 -or $Definition['tool_choice'] -cne 'none') {
        throw 'Only a minimal prompt definition without tools is supported.'
    }
    $format = $Definition['text']['format']
    if ($format['type'] -cne 'json_schema' -or $format['strict'] -ne $true) { throw 'Strict structured output is required.' }
    $normalized = New-AzdFoundryAgentDefinition -ModelDeployment $Definition['model'] -Instructions $Definition['instructions'] -OutputSchema $format['schema'] -SchemaName $format['name']
    if ((ConvertTo-AzdFoundryCanonicalJson $normalized) -cne (ConvertTo-AzdFoundryCanonicalJson $Definition)) {
        throw 'Unexpected prompt definition properties.'
    }
}

function Invoke-AzdFoundryHttp {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST')][string] $Method,
        [Parameter(Mandatory)][uri] $Uri,
        [Parameter(Mandatory)][securestring] $AccessToken,
        [string] $BodyJson
    )
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $handler.UseCookies = $false
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(120)
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Uri)
    $response = $null
    $stream = $null
    $memory = $null
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($AccessToken)
        $tokenText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        $request.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $tokenText)
        $tokenText = $null
        if ($Method -eq 'POST') { $request.Content = [Net.Http.StringContent]::new($BodyJson, [Text.Encoding]::UTF8, 'application/json') }
        $response = $client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $code = [int] $response.StatusCode
        if ($code -lt 200 -or $code -ge 300) {
            $category = if ($code -in 401, 403) { 'authentication-or-authorization' } elseif ($code -eq 429) { 'throttled' } else { 'service-or-configuration' }
            throw [InvalidOperationException]::new("Foundry HTTP $code ($category). No automatic retry was performed.")
        }
        if ($response.Content.Headers.ContentLength -gt 1048576) { throw [InvalidOperationException]::new('Foundry response exceeds the 1 MiB limit.') }
        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $memory = [IO.MemoryStream]::new()
        $buffer = [byte[]]::new(8192)
        # HttpClient timeout does not cover streamed reads. Use a separate deadline for the body.
        $deadline = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(120))
        try {
            while (($count = $stream.ReadAsync($buffer, 0, $buffer.Length, $deadline.Token).GetAwaiter().GetResult()) -gt 0) {
                if ($memory.Length + $count -gt 1048576) { throw [InvalidOperationException]::new('Foundry response exceeds the 1 MiB limit.') }
                $memory.Write($buffer, 0, $count)
            }
        }
        finally { $deadline.Dispose() }
        try { return [Text.Encoding]::UTF8.GetString($memory.ToArray()) | ConvertFrom-Json -AsHashtable -Depth 40 -ErrorAction Stop }
        catch { throw [InvalidOperationException]::new('Foundry returned invalid or excessively nested JSON.') }
    }
    catch {
        # Never propagate SDK/HTTP response bodies, headers, input, output or bearer tokens.
        if ($_.Exception -is [InvalidOperationException] -and $_.Exception.Message -cmatch '^Foundry (HTTP \d{3} |response exceeds |returned invalid )') {
            throw $_.Exception.Message
        }
        throw 'Foundry request did not return a verified result. The outcome may be unknown; reconcile before retrying.'
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        if ($stream) { $stream.Dispose() }
        if ($memory) { $memory.Dispose() }
        if ($response) { $response.Dispose() }
        $request.Dispose(); $client.Dispose(); $handler.Dispose()
    }
}

function Test-AzdFoundryAgentVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectEndpoint,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\z')][string] $AgentName,
        [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,15}\z')][string] $AgentVersion,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Definition,
        [Parameter(Mandatory)][securestring] $AccessToken
    )
    $endpoint = Resolve-AzdFoundryProjectEndpoint $ProjectEndpoint
    Assert-AzdFoundryDefinition $Definition
    $actual = Invoke-AzdFoundryHttp -Method GET -Uri "$endpoint/agents/$AgentName/versions/${AgentVersion}?api-version=v1" -AccessToken $AccessToken
    if ($actual['name'] -cne $AgentName -or [string]$actual['version'] -cne $AgentVersion -or $actual['definition'] -isnot [System.Collections.IDictionary]) {
        throw 'Foundry agent readback did not identify the exact requested name and version.'
    }
    $remote = $actual['definition']
    foreach ($key in $Definition.Keys) {
        if ((ConvertTo-AzdFoundryCanonicalJson $remote[$key]) -cne (ConvertTo-AzdFoundryCanonicalJson $Definition[$key])) {
            throw 'Foundry agent definition readback differs from the reviewed definition.'
        }
    }
    # Fail closed on newly surfaced behavior until the component explicitly reviews it.
    foreach ($key in $remote.Keys) {
        if (-not $Definition.Contains($key) -and $null -ne $remote[$key]) {
            throw 'Foundry agent readback contains an unreviewed definition property.'
        }
    }
    return [ordered]@{
        schemaVersion = '1.0'; componentVersion = '0.1.1'; status = 'verified'
        projectEndpoint = $endpoint; agentName = $AgentName; agentVersion = $AgentVersion
        modelDeployment = $Definition['model']; definitionSha256 = Get-AzdFoundryTextHash (ConvertTo-AzdFoundryCanonicalJson $Definition)
    }
}

function Publish-AzdFoundryAgentVersion {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $ProjectEndpoint,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\z')][string] $AgentName,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Definition,
        [Parameter(Mandatory)][securestring] $AccessToken
    )
    $endpoint = Resolve-AzdFoundryProjectEndpoint $ProjectEndpoint
    Assert-AzdFoundryDefinition $Definition
    if (-not $PSCmdlet.ShouldProcess("$endpoint/agents/$AgentName", 'Create a new prompt agent version and verify readback')) { return }
    $body = @{ definition = $Definition } | ConvertTo-Json -Depth 40 -Compress
    $created = Invoke-AzdFoundryHttp -Method POST -Uri "$endpoint/agents/$AgentName/versions?api-version=v1" -AccessToken $AccessToken -BodyJson $body
    if ($created['name'] -cne $AgentName -or [string]$created['version'] -cnotmatch '^[1-9][0-9]{0,15}\z') {
        throw 'Foundry creation returned no exact version. Reconcile the unknown result before creating another version.'
    }
    return Test-AzdFoundryAgentVersion -ProjectEndpoint $endpoint -AgentName $AgentName -AgentVersion ([string]$created['version']) -Definition $Definition -AccessToken $AccessToken
}

function Invoke-AzdFoundryStatelessResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ProjectEndpoint,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\z')][string] $AgentName,
        [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,15}\z')][string] $AgentVersion,
        [Parameter(Mandatory)][System.Collections.IDictionary] $Definition,
        [Parameter(Mandatory)][securestring] $AccessToken,
        [Parameter(Mandatory)][System.Collections.IDictionary] $VerificationReceipt,
        [Parameter(Mandatory)][ValidateLength(1, 65536)][string] $InputText,
        [ValidateRange(256, 8192)][int] $MaxOutputTokens = 2048
    )
    if ([Text.Encoding]::UTF8.GetByteCount($InputText) -gt 65536) { throw 'Input exceeds 65536 UTF-8 bytes.' }
    $endpoint = Resolve-AzdFoundryProjectEndpoint $ProjectEndpoint
    Assert-AzdFoundryDefinition $Definition
    $expected = [ordered]@{
        schemaVersion = '1.0'; componentVersion = '0.1.1'; status = 'verified'
        projectEndpoint = $endpoint; agentName = $AgentName; agentVersion = $AgentVersion
        modelDeployment = $Definition['model']; definitionSha256 = Get-AzdFoundryTextHash (ConvertTo-AzdFoundryCanonicalJson $Definition)
    }
    foreach ($key in $expected.Keys) {
        if ($VerificationReceipt[$key] -cne $expected[$key]) { throw 'The setup verification receipt does not match this exact agent configuration.' }
    }
    # Saved agent versions are immutable. Reuse the protected setup receipt without granting runtime definition-read authority.
    $receipt = $expected
    $body = [ordered]@{
        agent_reference = @{ type = 'agent_reference'; name = $AgentName; version = $AgentVersion }
        input = $InputText; store = $false; stream = $false; background = $false
        tools = @(); tool_choice = 'none'; parallel_tool_calls = $false; max_output_tokens = $MaxOutputTokens
    } | ConvertTo-Json -Depth 40 -Compress
    $response = Invoke-AzdFoundryHttp -Method POST -Uri "$($receipt.projectEndpoint)/openai/v1/responses" -AccessToken $AccessToken -BodyJson $body
    if ($response['status'] -cne 'completed' -or $response['error'] -or $response['incomplete_details'] -or
        $response['store'] -isnot [bool] -or $response['store'] -ne $false -or $response['background'] -or $response['conversation'] -or $response['previous_response_id']) {
        throw 'Foundry response is incomplete, failed, stored or linked to conversation state; it cannot be used.'
    }
    if ($response['agent_reference'] -and ($response['agent_reference']['name'] -cne $AgentName -or [string]$response['agent_reference']['version'] -cne $AgentVersion)) {
        throw 'Foundry response identifies a different agent version.'
    }
    $texts = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $response['output']) {
        if ($item['type'] -ceq 'reasoning') { continue }
        if ($item['type'] -cne 'message' -or $item['role'] -cne 'assistant' -or $item['status'] -cne 'completed') {
            throw 'Foundry response contains a tool call or unexpected output item.'
        }
        foreach ($part in $item['content']) {
            if ($part['type'] -cne 'output_text' -or $part['text'] -isnot [string]) { throw 'Foundry response contains refusal or unsupported content.' }
            $texts.Add($part['text'])
        }
    }
    $outputText = $texts -join "`n"
    if (-not $outputText -or [Text.Encoding]::UTF8.GetByteCount($outputText) -gt 65536) { throw 'Foundry output is empty or exceeds 65536 UTF-8 bytes.' }
    $schema = ConvertTo-AzdFoundryCanonicalJson $Definition['text']['format']['schema']
    try {
        if (-not (Test-Json -Json $outputText -Schema $schema -ErrorAction Stop)) { throw 'Invalid output.' }
        $result = ConvertFrom-Json -InputObject $outputText -AsHashtable -Depth 40 -ErrorAction Stop
    }
    catch { throw 'Foundry output does not match the reviewed JSON schema.' }
    $receipt.status = 'completed'
    $receipt['inputSha256'] = Get-AzdFoundryTextHash $InputText
    $receipt['outputSha256'] = Get-AzdFoundryTextHash $outputText
    $receipt['store'] = $false
    if ($response['usage'] -is [System.Collections.IDictionary]) {
        $usage = @{}
        foreach ($key in @('input_tokens', 'output_tokens', 'total_tokens')) {
            $value = $response['usage'][$key]
            if ($value -isnot [long] -and $value -isnot [int]) { throw 'Foundry returned invalid token usage metadata.' }
            if ($value -lt 0) { throw 'Foundry returned invalid token usage metadata.' }
            $usage[$key] = $value
        }
        $receipt['usage'] = $usage
    }
    # Consumer owns the result's data classification, review and storage. The receipt is metadata only.
    return @{ result = $result; receipt = $receipt }
}

Export-ModuleMember -Function New-AzdFoundryAgentDefinition, Publish-AzdFoundryAgentVersion, Test-AzdFoundryAgentVersion, Invoke-AzdFoundryStatelessResponse
