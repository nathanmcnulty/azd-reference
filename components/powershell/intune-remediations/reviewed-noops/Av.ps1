[CmdletBinding()]
param()

$result = [ordered]@{
    schemaVersion = '1.0'
    status = 'noop'
    changed = $false
    reason = 'Inventory collection never changes Microsoft Defender Antivirus exclusions.'
}
[Console]::Out.WriteLine(($result | ConvertTo-Json -Compress))
exit 0
