BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot '../components/powershell/security-automation-runtime/Azd.SecurityAutomation.psm1') -Force
}
Describe 'Explicit security operator target at Blob and token boundaries' {
    InModuleScope Azd.SecurityAutomation {
        BeforeAll {
            function az { param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments) }
        }
        BeforeEach {
            $script:sub='11111111-1111-4111-8111-111111111111'
            $script:tenant='22222222-2222-4222-8222-222222222222'
            $script:context=@{SubscriptionId=$script:sub;TenantId=$script:tenant}
            $script:account=@{id=$script:sub;tenantId=$script:tenant;environmentName='AzureCloud'}
            $script:metadata=@{id="/subscriptions/$script:sub";subscriptionId=$script:sub;tenantId=$script:tenant;state='Enabled'}
            $script:resource=@{id="/subscriptions/$script:sub/resourceGroups/group/providers/Microsoft.Storage/storageAccounts/teststorage";name='teststorage';type='Microsoft.Storage/storageAccounts';properties=@{primaryEndpoints=@{blob='https://teststorage.blob.core.windows.net/'}}}
            $script:token=@{accessToken='synthetic-token';tenant=$script:tenant;subscription=$script:sub}
            $script:reads=0; $script:disableAfter=0
            Mock az {
                $global:LASTEXITCODE=0
                if ($Arguments[0] -ne 'account') { throw 'Unexpected CLI call.' }
                if ($Arguments[1] -eq 'show') {
                    if (($Arguments -join ' ') -notlike "*--subscription $script:sub *") { throw 'Default context used.' }
                    return $script:account | ConvertTo-Json -Compress
                }
                if ($Arguments[1] -eq 'get-access-token') {
                    if ($Arguments -contains '--tenant' -and $Arguments -contains '--subscription') { throw 'Azure CLI selector flags are mutually exclusive.' }
                    if (($Arguments -join ' ') -notlike "*--subscription $script:sub*" -and ($Arguments -join ' ') -notlike "*--tenant $script:tenant*") { throw 'Explicit context omitted.' }
                    return $script:token | ConvertTo-Json -Compress
                }
                throw 'Unexpected CLI account call.'
            }
            Mock Invoke-RestMethod {
                if ($Method -ne 'Get' -or $MaximumRedirection -ne 0 -or $Headers.Authorization -ne 'Bearer synthetic-token') { throw 'Unexpected HTTP boundary.' }
                if ($Uri -eq "https://management.azure.com/subscriptions/$($script:sub)?api-version=2022-12-01") {
                    $script:reads++
                    if ($script:disableAfter -and $script:reads -ge $script:disableAfter) { $script:metadata.state='Disabled' }
                    return [pscustomobject]$script:metadata
                }
                if ($Uri -eq "https://management.azure.com$($script:resource.id)?api-version=2023-05-01") { return [pscustomobject]$script:resource }
                throw 'Unexpected metadata URL.'
            }
            Mock Invoke-WebRequest { throw 'Unexpected Blob write.' }
            $script:package=Join-Path $TestDrive 'package.zip'; Set-Content $script:package 'approved'
            $script:upload=@{Account='teststorage';Container='packages';Blob='approved.zip';Path=$script:package;Direction='Upload';AuthMode='AzureCli';ResourceGroup='group'}
        }
        It 'rejects omitted, empty, malformed and zero selectors before token acquisition' {
            foreach ($value in @('', 'bad', '00000000-0000-0000-0000-000000000000', "$script:sub`n")) {
                { Invoke-SecurityBlobTransfer @script:upload -SubscriptionId $value -TenantId $script:tenant } | Should -Throw
                { Invoke-SecurityBlobTransfer @script:upload -SubscriptionId $script:sub -TenantId $value } | Should -Throw
            }
            Should -Invoke az -Times 0 -Exactly
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }
        It 'rejects unapproved CLI account identity: <Field>' -ForEach @(@{Field='id'},@{Field='tenantId'},@{Field='environmentName'}) {
            $script:account[$Field]='wrong'
            { Invoke-SecurityBlobTransfer @script:upload @script:context } | Should -Throw
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }
        It 'rejects missing, malformed or non-Enabled ARM metadata: <Field> <Value>' -ForEach @(
            @{Field='id';Value='/subscriptions/other'},@{Field='subscriptionId';Value='other'},@{Field='tenantId';Value='other'},
            @{Field='state';Value='Disabled'},@{Field='state';Value='enabled'},@{Field='state';Value=$null},@{Field='state';Value=@('Enabled','Disabled')}
        ) {
            $script:metadata[$Field]=$Value
            { Invoke-SecurityBlobTransfer @script:upload @script:context } | Should -Throw
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }
        It 'rejects metadata transport failure without a Blob request' {
            Mock Invoke-RestMethod { throw 'metadata unavailable' }
            { Invoke-SecurityBlobTransfer @script:upload @script:context } | Should -Throw
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }
        It 'rejects mismatched resource identity and endpoint: <Field>' -ForEach @(@{Field='id'},@{Field='name'},@{Field='type'},@{Field='endpoint'}) {
            if ($Field -eq 'endpoint') { $script:resource.properties.primaryEndpoints.blob='https://other.blob.core.windows.net/' }
            else { $script:resource[$Field]='other' }
            { Invoke-SecurityBlobTransfer @script:upload @script:context } | Should -Throw
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }
        It 'checks fresh subscription state after resource lookup before upload' {
            $script:disableAfter=2
            { Invoke-SecurityBlobTransfer @script:upload @script:context } | Should -Throw
            $script:reads | Should -Be 2
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }
        It 'uploads once with scoped credentials and immutable condition, without changing CLI defaults' {
            Mock Invoke-WebRequest { }
            Invoke-SecurityBlobTransfer @script:upload @script:context
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://teststorage.blob.core.windows.net/packages/approved.zip' -and $Method -eq 'Put' -and
                $Headers['If-None-Match'] -eq '*' -and $MaximumRedirection -eq 0 -and $InFile -eq $script:package
            }
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { $Arguments[1] -eq 'set' }
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { $Arguments[1] -eq 'get-access-token' -and ($Arguments -join ' ') -notlike "*--subscription $script:sub*" }
        }
        It 'fails closed on a different token tenant or subscription without HTTP' {
            foreach ($field in @('tenant','subscription')) {
                $saved=$script:token[$field]; $script:token[$field]='other'
                { Invoke-SecurityBlobTransfer @script:upload @script:context } | Should -Throw
                $script:token[$field]=$saved
            }
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        }
        It 'verifies immutable CLI collision with fresh guarded readback: <Matches>' -ForEach @(@{Matches=$true},@{Matches=$false}) {
            $script:collisionMatches=$Matches
            Mock Invoke-WebRequest {
                if ($Method -eq 'Put') {
                    $exception=[Exception]::new('already exists')
                    $exception | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{StatusCode=412})
                    throw $exception
                }
                if ($script:collisionMatches) { Copy-Item -LiteralPath $script:package -Destination $OutFile }
                else { Set-Content -LiteralPath $OutFile 'different' }
            }
            if ($Matches) { Invoke-SecurityBlobTransfer @script:upload @script:context }
            else { { Invoke-SecurityBlobTransfer @script:upload @script:context } | Should -Throw '*Immutable package verification failed*' }
            $script:reads | Should -Be 4
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'Put' -and $Headers['If-None-Match'] -eq '*' }
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $OutFile -and $Uri -eq 'https://teststorage.blob.core.windows.net/packages/approved.zip' -and $MaximumRedirection -eq 0
            }
            Should -Invoke az -Times 0 -Exactly -ParameterFilter { $Arguments[1] -eq 'get-access-token' -and $Arguments -notcontains '--subscription' }
        }
        It 'stops immutable CLI collision readback when the subscription becomes Disabled' {
            $script:disableAfter=3
            Mock Invoke-WebRequest {
                if ($Method -ne 'Put') { throw 'Unexpected collision readback.' }
                $exception=[Exception]::new('already exists')
                $exception | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{StatusCode=412})
                throw $exception
            }
            { Invoke-SecurityBlobTransfer @script:upload @script:context } | Should -Throw '*Immutable package verification failed*'
            $script:reads | Should -Be 3
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly
        }
        It 'preserves tenant-only Graph token requests without an ARM lookup' {
            Get-SecurityAccessToken -Resource 'https://graph.microsoft.com' -AuthMode AzureCli -TenantId $script:tenant | Should -Be 'synthetic-token'
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
            Should -Invoke az -Times 1 -Exactly -ParameterFilter { $Arguments -notcontains '--subscription' }
        }
        It 'preserves managed identity uploads without CLI or ARM dependencies' {
            Mock Get-SecurityAccessToken { 'synthetic-managed-token' }
            Mock Invoke-WebRequest { }
            Invoke-SecurityBlobTransfer -Account teststorage -Container reports -Blob result.json -Path $script:package -Direction Upload
            Should -Invoke az -Times 0 -Exactly
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Headers.Authorization -eq 'Bearer synthetic-managed-token' }
        }
    }
}
