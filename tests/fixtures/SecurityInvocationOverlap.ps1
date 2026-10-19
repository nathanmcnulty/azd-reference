# Actual canonical wrapper, bundle dispatcher and resolver; only provenance/Blob I/O are replaced.
# Synchronization derives from the retained actual AppControl reproduction described in README.
function Invoke-SecurityInvocationOverlapFixture {
    param([string]$ModulePath,[string]$Root,[ValidateSet('A','B')][string]$First='A',[bool]$FailFirst=$false,[AllowNull()][string]$OriginalEnvironment)
    $oldEnvironment=$env:SECURITY_EVIDENCE_ROOT
    $env:SECURITY_EVIDENCE_ROOT=$OriginalEnvironment
    $sync=@{
        entered=@{A=[Threading.ManualResetEventSlim]::new($false);B=[Threading.ManualResetEventSlim]::new($false)}
        completed=@{A=[Threading.ManualResetEventSlim]::new($false);B=[Threading.ManualResetEventSlim]::new($false)}
        roots=[Collections.Concurrent.ConcurrentDictionary[string,string]]::new()
        observations=[Collections.Concurrent.ConcurrentQueue[object]]::new()
    }
    $null=New-Item -ItemType Directory $Root -Force
    $outside=Join-Path $Root outside.txt
    Set-Content $outside 'synthetic outside file'
    $configuration=Join-Path $Root config.json
    @{schemaVersion='2.0';solutions=@(@{id='azd-synthetic';runner='runner.ps1';runnerContractVersion='2.0';input='input.json'})} | ConvertTo-Json -Depth 5 | Set-Content $configuration
    Set-Content (Join-Path $Root runner.ps1) @'
[CmdletBinding()]
param($InputPath,$OutputDirectory,$InvocationContext)
$p=$global:SecurityInvocationProbe
$role=$p.role; $other=if($role -eq 'A'){'B'}else{'A'}
$root=Split-Path $InputPath
if ($InvocationContext -isnot [Collections.Immutable.ImmutableDictionary[string,string]]) { throw 'Context type was not preserved.' }
if ($InvocationContext['mode'] -cne 'Hosted' -or $InvocationContext['evidenceRoot'] -cne $root) { throw 'Wrong invocation context.' }
$p.sync.roots[$role]=$root
$p.sync.entered[$role].Set()
if (-not $p.sync.entered[$other].Wait(10000)) { throw 'Peer did not enter.' }
# Both real invocations have entered. First checks while both roots exist; second after peer cleanup.
if ($role -ne $p.first -and -not $p.sync.completed[$other].Wait(10000)) { throw 'Peer did not finish.' }
if ($env:SECURITY_EVIDENCE_ROOT -cne $p.originalEnvironment) { throw 'Process environment changed.' }
$own=Resolve-SecurityEvidencePath -Path $InputPath -InputDirectory $root -InvocationContext $InvocationContext
if ($own -cne $InputPath) { throw 'Own input was not accepted.' }
foreach ($path in @((Join-Path $p.sync.roots[$other] input.json),$p.outside)) {
    $denied=$false
    try { $null=Resolve-SecurityEvidencePath -Path $path -InputDirectory $root -InvocationContext $InvocationContext }
    catch { if ($_.Exception.Message -notlike '*escapes*') { throw }; $denied=$true }
    if (-not $denied) { throw 'Cross/outside evidence was accepted.' }
}
if ($role -ne $p.first -and (Test-Path $p.sync.roots[$other])) { throw 'Completed peer root was not cleaned.' }
if (-not (Test-Path $root)) { throw 'Own root was cleaned by another invocation.' }
# A nested bounded context is a separate immutable value; it does not replace the caller.
$nested=Join-Path $OutputDirectory snapshot
$null=New-Item -ItemType Directory $nested
Set-Content (Join-Path $nested nested.txt) synthetic
$nestedContext=New-SecurityInvocationContext -Mode Hosted -EvidenceRoot $nested
$null=Resolve-SecurityEvidencePath -Path nested.txt -InputDirectory $nested -InvocationContext $nestedContext
if ($nestedContext['invocationId'] -eq $InvocationContext['invocationId']) { throw 'Nested context reused caller identity.' }
$null=Resolve-SecurityEvidencePath -Path $InputPath -InputDirectory $root -InvocationContext $InvocationContext
$p.sync.observations.Enqueue([pscustomobject]@{role=$role;root=$root;id=$InvocationContext['invocationId'];ownAllowed=$true;crossDenied=$true;outsideDenied=$true;peerCleaned=($role -ne $p.first)})
if ($role -eq $p.first -and $p.failFirst) { throw 'Injected first invocation failure.' }
'@
    $worker={
        param($modulePath,$sync,$role,$first,$failFirst,$root,$configuration,$outside,$originalEnvironment)
        function global:Invoke-RestMethod { throw 'Unexpected HTTP is prohibited.' }
        function global:Invoke-WebRequest { throw 'Unexpected HTTP is prohibited.' }
        function global:az { throw 'Unexpected Azure CLI is prohibited.' }
        function global:azd { throw 'Unexpected azd is prohibited.' }
        $global:SecurityInvocationProbe=@{sync=$sync;role=$role;first=$first;failFirst=$failFirst;outside=$outside;originalEnvironment=$originalEnvironment}
        $module=Import-Module $modulePath -Force -PassThru
        & $module {
            function script:Get-SecurityAccessToken { throw 'Unexpected token acquisition is prohibited.' }
            function script:Get-SecurityBundleProvenance { @{manifestSha256=('a'*64);sourceCommits=@()} }
            function script:Invoke-SecurityBlobTransfer {
                param($Account,$Container,$Blob,$Path,$Direction='Download')
                if($Direction -eq 'Download') { Set-Content -LiteralPath $Path '{}' }
            }
        }
        try {
            $result=Invoke-HostedSecurityBundle -BundleRoot $root -ConfigurationPath $configuration -Account synthetic
            [pscustomobject]@{role=$role;status=$result.status;error=$null}
        } catch { [pscustomobject]@{role=$role;status='failed';error=$_.Exception.Message} }
        finally { $sync.completed[$role].Set() }
    }
    $a=[PowerShell]::Create();$b=[PowerShell]::Create()
    try {
        foreach($pair in @(@($a,'A'),@($b,'B'))) {
            $null=$pair[0].AddScript($worker)
            foreach($argument in @($ModulePath,$sync,$pair[1],$First,$FailFirst,$Root,$configuration,$outside,$OriginalEnvironment)) { $null=$pair[0].AddArgument($argument) }
        }
        $ha=$a.BeginInvoke();$hb=$b.BeginInvoke()
        if(-not $ha.AsyncWaitHandle.WaitOne(20000) -or -not $hb.AsyncWaitHandle.WaitOne(20000)) { throw 'Bounded overlap fixture timed out.' }
        $results=@($a.EndInvoke($ha)) + @($b.EndInvoke($hb))
        foreach ($errorRecord in @($a.Streams.Error) + @($b.Streams.Error)) {
            if (-not $FailFirst -or $errorRecord.Exception.Message -cne 'Injected first invocation failure.') { throw "Unexpected runspace error: $errorRecord" }
        }
        if ($sync.observations.Count -ne 2) { throw "Missing successful isolation observations: $($results | ConvertTo-Json -Compress)" }
        foreach($result in $results) {
            if($result.role -eq $First -and $FailFirst) {
                if($result.error -cne 'Injected first invocation failure.') { throw 'Unexpected first invocation failure.' }
            } elseif($result.status -cne 'review-produced') { throw 'Invocation did not complete.' }
        }
        if(@($sync.roots.Values | Where-Object { Test-Path $_ }).Count -ne 0) { throw 'Owned temporary root leaked.' }
        if($env:SECURITY_EVIDENCE_ROOT -cne $OriginalEnvironment) { throw 'Original process environment was not preserved.' }
        return $sync.observations.ToArray()
    } finally {
        foreach($role in @('A','B')) { $sync.entered[$role].Set();$sync.completed[$role].Set() }
        $a.Stop();$b.Stop();$a.Dispose();$b.Dispose()
        foreach($role in @('A','B')) { $sync.entered[$role].Dispose();$sync.completed[$role].Dispose() }
        $env:SECURITY_EVIDENCE_ROOT=$oldEnvironment
    }
}
