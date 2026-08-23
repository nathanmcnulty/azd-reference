[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [string[]] $Path
)

begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $sensitiveNamePattern = '(?i)(authorization|identity.?header|(?:access|refresh|bearer|id)?.?token|password|secret|credential|cookie|assertion|certificate|(?:private|api|account|subscription|host|function)?.?key|connection.?string|shared.?access.?signature|callback|webhook.?url|sas|signature)'
    $sensitiveValuePatterns = @(
        '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+',
        '(?i)[?&](sig|signature|token|code|key|secret|sas)=',
        '(?i)%3[fF](sig|signature|token|code|key|secret|sas)%3[dD]',
        '(?i)(AccountKey|SharedAccessSignature|ClientSecret|Password|ConnectionString)=',
        '(?i)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
    )

    function Find-SensitiveContractValue {
        param(
            [AllowNull()][object] $Value,
            [Parameter(Mandatory)][string] $JsonPath,
            [string] $Name = ''
        )

        $findings = [System.Collections.Generic.List[string]]::new()
        if ($Name -ine 'idempotencyKey' -and $Name -match $sensitiveNamePattern) {
            $findings.Add("$JsonPath uses a credential-bearing property name")
            return @($findings)
        }
        if ($null -eq $Value -or $Value -is [ValueType]) { return @() }
        if ($Value -is [string]) {
            foreach ($pattern in $sensitiveValuePatterns) {
                if ($Value -match $pattern) {
                    $findings.Add("$JsonPath contains a credential-bearing value shape")
                    break
                }
            }
            return @($findings)
        }
        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($key in $Value.Keys) {
                foreach ($finding in @(Find-SensitiveContractValue `
                    -Value $Value[$key] `
                    -JsonPath "$JsonPath.$key" `
                    -Name ([string] $key))) {
                    $findings.Add($finding)
                }
            }
            return @($findings)
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            $index = 0
            foreach ($item in $Value) {
                foreach ($finding in @(Find-SensitiveContractValue `
                    -Value $item `
                    -JsonPath "$JsonPath[$index]" `
                    -Name $Name)) {
                    $findings.Add($finding)
                }
                $index++
            }
            return @($findings)
        }
        foreach ($property in $Value.PSObject.Properties) {
            foreach ($finding in @(Find-SensitiveContractValue `
                -Value $property.Value `
                -JsonPath "$JsonPath.$($property.Name)" `
                -Name $property.Name)) {
                $findings.Add($finding)
            }
        }
        return @($findings)
    }
}

process {
    foreach ($inputPath in $Path) {
        $resolvedPath = (Resolve-Path -LiteralPath $inputPath -ErrorAction Stop).Path
        $document = Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json -Depth 100
        $findings = @(Find-SensitiveContractValue -Value $document -JsonPath '$')
        if ($findings.Count -gt 0) {
            throw "Notification contract safety validation failed for '$resolvedPath': $($findings -join '; ')."
        }
        [pscustomobject]@{
            path = $resolvedPath
            safe = $true
        }
    }
}
