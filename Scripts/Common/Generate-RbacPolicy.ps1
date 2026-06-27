<#
.SYNOPSIS
    Auto-generates a least-privilege custom RBAC role + a deny Azure Policy for a finished
    CloudLabs lab, by scanning the resources that the lab actually provisioned.

.DESCRIPTION
    Run this ONCE on the jump VM (elevated PowerShell) AFTER all lab exercises are complete and
    every resource has been deployed. It reads the live state of the lab resource group and emits
    two JSON files matching the curated CloudLabs format:

        <OutputRoot>/<LabName>/cust-rbac.json      - custom role definition
        <OutputRoot>/<LabName>/custom-policy.json  - deny policy (unused types + oversized SKUs)

    Discovery is automatic and layered (each value falls back to the next source):
        explicit parameter  ->  C:\LabFiles\AzureCreds.ps1 / .txt  ->  Azure IMDS  ->  interactive

    Design choices:
      * Generous, not narrow: grants "<Provider>/*" for every provider the lab used; the policy
        only blocks resource TYPES that were never used and SKUs/sizes outside what was observed.
      * NO location/region restrictions (CloudLabs provisions per the ODL region array).
      * Policy SKU field names ("aliases") are resolved against the LIVE Azure alias catalog
        (Get-AzPolicyAlias) so the output never depends on hard-coded property paths that rot.
      * Generate-only: writes JSON for review. It does NOT create the role/policy in Azure.

    Built on the Az PowerShell module (installed by InstallAzPowerShellModule in
    Scripts/Common/cloudlabs-windows-functions.ps1). The legacy AzureRM module is not used.

.EXAMPLE
    # On the jump VM after the lab is finished - fully automatic:
    .\Generate-RbacPolicy.ps1

.EXAMPLE
    # Manual run from an ODL Azure CLI / Cloud Shell session:
    .\Generate-RbacPolicy.ps1 -SubscriptionId <sub> -ResourceGroup <rg> -LabName "RevOps HIAD"

.EXAMPLE
    # Preview the resolved context and planned output without scanning or writing:
    .\Generate-RbacPolicy.ps1 -DryRun

.NOTES
    Everything environment-specific is a parameter (below) or lives in rbac-baseline.json.
    Nothing per-lab or per-subscription is hard-coded in the body.
#>

[CmdletBinding()]
param(
    [string] $SubscriptionId,
    [string] $TenantId,
    [string] $ResourceGroup,
    [string] $DeploymentId,
    [string] $LabName,

    # Where the per-lab folder of JSON files is written. Default resolved below from script dir.
    [string] $OutputRoot,

    # CloudLabs credential file dropped on every jump VM by CreateCredFile().
    [string] $CredsPath = 'C:\LabFiles\AzureCreds.ps1',

    # Editable guardrail template (sits next to this script). Default resolved below from script dir.
    [string] $BaselinePath,

    # By default AssignableScopes keeps the <SUBSCRIPTION_ID> placeholder (portable across deployments).
    # Pass -SubstituteScope to write the real subscription id instead.
    [switch] $SubstituteScope,

    # Resolve context and report the plan without contacting Azure or writing files.
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Resolve script-relative defaults safely (works when run normally or dot-sourced for testing).
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot }
             elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath }
             else { (Get-Location).Path }
if (-not $OutputRoot)   { $OutputRoot   = Join-Path $ScriptDir '..\..\RBAC\Policies\Lab-generated-policies' }
if (-not $BaselinePath) { $BaselinePath = Join-Path $ScriptDir 'rbac-baseline.json' }

# ----------------------------------------------------------------------------------------------
#  Logging helpers
# ----------------------------------------------------------------------------------------------
function Write-Info  ($m) { Write-Host "[INFO ] $m" -ForegroundColor Cyan }
function Write-Good  ($m) { Write-Host "[ OK  ] $m" -ForegroundColor Green }
function Write-Warn2 ($m) { Write-Host "[WARN ] $m" -ForegroundColor Yellow }
function Write-Err   ($m) { Write-Host "[FAIL ] $m" -ForegroundColor Red }

# Distinct, trimmed, non-empty string values from a (possibly null/scalar) input.
function Get-DistinctValues {
    param($Values)
    if ($null -eq $Values) { return @() }
    return @($Values |
        ForEach-Object { if ($null -ne $_) { "$_".Trim() } } |
        Where-Object   { $_ -and $_ -ne 'null' } |
        Select-Object -Unique |
        Sort-Object)
}

# ----------------------------------------------------------------------------------------------
#  1. Context resolution  (param -> AzureCreds -> IMDS -> interactive)
# ----------------------------------------------------------------------------------------------
function Read-AzureCreds {
    param([string]$Ps1Path)
    $bag = @{}
    # Prefer the .txt sibling (documented "Key= value" format), then dot-source the .ps1.
    $txtPath = [System.IO.Path]::ChangeExtension($Ps1Path, '.txt')
    if (Test-Path $txtPath) {
        foreach ($line in Get-Content $txtPath) {
            if ($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.+?)\s*$') {
                $bag[$Matches[1]] = $Matches[2].Trim()
            }
        }
    }
    if (Test-Path $Ps1Path) {
        # Dot-source in a child scope so the $Azure* variables it defines become readable here.
        try {
            . $Ps1Path
            foreach ($n in 'AzureSubscriptionID','AzureTenantID','DeploymentID',
                           'AzureServicePrincipalAppID','AzureServicePrincipalSecretKey',
                           'AzureTenantDomainName') {
                $v = Get-Variable -Name $n -ValueOnly -ErrorAction SilentlyContinue
                if ($v) { $bag[$n] = "$v" }
            }
        } catch { Write-Warn2 "Could not dot-source $Ps1Path : $_" }
    }
    return $bag
}

function Get-ImdsCompute {
    try {
        return Invoke-RestMethod -Headers @{ Metadata = 'true' } -TimeoutSec 5 -UseBasicParsing `
            -Uri 'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01'
    } catch {
        Write-Warn2 "Azure IMDS not reachable (not on an Azure VM?): $_"
        return $null
    }
}

function Resolve-LabContext {
    Write-Info 'Resolving lab context...'
    $creds = Read-AzureCreds -Ps1Path $CredsPath
    $imds  = Get-ImdsCompute

    $ctx = [ordered]@{
        SubscriptionId = $SubscriptionId
        TenantId       = $TenantId
        ResourceGroup  = $ResourceGroup
        DeploymentId   = $DeploymentId
        LabName        = $LabName
        SpAppId        = $null
        SpSecret       = $null
        AuthMethod     = 'interactive'
    }

    if (-not $ctx.SubscriptionId) { $ctx.SubscriptionId = $creds['AzureSubscriptionID'] }
    if (-not $ctx.SubscriptionId -and $imds) { $ctx.SubscriptionId = $imds.subscriptionId }

    if (-not $ctx.TenantId)     { $ctx.TenantId     = $creds['AzureTenantID'] }
    if (-not $ctx.DeploymentId) { $ctx.DeploymentId = $creds['DeploymentID'] }

    # RG: prefer the one the jump VM itself lives in (single-RG labs), then deployment-id naming.
    if (-not $ctx.ResourceGroup -and $imds) { $ctx.ResourceGroup = $imds.resourceGroupName }

    # Service principal for headless login.
    $ctx.SpAppId  = $creds['AzureServicePrincipalAppID']
    $ctx.SpSecret = $creds['AzureServicePrincipalSecretKey']
    if ($ctx.SpAppId -and $ctx.SpSecret -and $ctx.TenantId) { $ctx.AuthMethod = 'serviceprincipal' }

    # Interactive last-resort prompts for the must-haves.
    if (-not $ctx.SubscriptionId) { $ctx.SubscriptionId = Read-Host 'Enter Subscription Id' }
    if (-not $ctx.ResourceGroup)  { $ctx.ResourceGroup  = Read-Host 'Enter lab Resource Group name' }

    if (-not $ctx.LabName) {
        $ctx.LabName = $ctx.ResourceGroup -replace '^challenge-rg-?','' -replace '[^A-Za-z0-9._-]','-'
        if (-not $ctx.LabName) { $ctx.LabName = $ctx.ResourceGroup }
    }
    return $ctx
}

# ----------------------------------------------------------------------------------------------
#  2. Azure connection
# ----------------------------------------------------------------------------------------------
function Connect-LabAzure {
    param($Ctx)
    Import-Module Az.Accounts -ErrorAction Stop | Out-Null

    $current = Get-AzContext -ErrorAction SilentlyContinue
    if ($current -and $current.Subscription.Id -eq $Ctx.SubscriptionId) {
        Write-Good "Already connected to subscription $($Ctx.SubscriptionId)."
        return
    }

    if ($Ctx.AuthMethod -eq 'serviceprincipal') {
        Write-Info 'Connecting with the lab service principal (headless)...'
        $sec  = ConvertTo-SecureString $Ctx.SpSecret -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ($Ctx.SpAppId, $sec)
        Connect-AzAccount -ServicePrincipal -Credential $cred -Tenant $Ctx.TenantId `
            -Subscription $Ctx.SubscriptionId -WarningAction SilentlyContinue | Out-Null
    } else {
        Write-Info 'No service principal available - launching interactive sign-in...'
        Connect-AzAccount -Tenant $Ctx.TenantId -Subscription $Ctx.SubscriptionId `
            -WarningAction SilentlyContinue | Out-Null
    }
    Set-AzContext -Subscription $Ctx.SubscriptionId -WarningAction SilentlyContinue | Out-Null
    Write-Good "Connected to subscription $($Ctx.SubscriptionId)."
}

# ----------------------------------------------------------------------------------------------
#  3. Resource inventory
# ----------------------------------------------------------------------------------------------
function Get-LabResourceTypes {
    param([string]$Rg)
    Write-Info "Enumerating resources in resource group '$Rg'..."
    $resources = @(Get-AzResource -ResourceGroupName $Rg -ErrorAction Stop)
    if (-not $resources) { Write-Warn2 "No resources found in '$Rg'." ; return @() }
    $types = Get-DistinctValues ($resources | Select-Object -ExpandProperty ResourceType)
    Write-Good "Found $($resources.Count) resources across $($types.Count) resource types."
    return $types
}

# ----------------------------------------------------------------------------------------------
#  4. Policy alias resolution  (keeps SKU field paths current, never hard-coded)
# ----------------------------------------------------------------------------------------------
$script:AliasCache = @{}
function Get-TypeAliasNames {
    param([string]$Type)
    if ($script:AliasCache.ContainsKey($Type)) { return $script:AliasCache[$Type] }
    $names = @()
    $parts = $Type -split '/', 2
    if ($parts.Count -eq 2) {
        try {
            $hits = Get-AzPolicyAlias -NamespaceMatch $parts[0] -ResourceTypeMatch $parts[1] -ErrorAction Stop
            $exact = $hits | Where-Object { "$($_.Namespace)/$($_.ResourceType)" -ieq $Type }
            if ($exact) { $names = @($exact.Aliases.Name) }
        } catch { Write-Warn2 "Alias lookup failed for $Type : $_" }
    }
    $script:AliasCache[$Type] = $names
    return $names
}

# Returns the first candidate suffix that exists as a real alias for $Type, else $null (skip the rule).
function Resolve-SkuAlias {
    param([string]$Type, [string[]]$CandidateSuffixes)
    $names = Get-TypeAliasNames -Type $Type
    foreach ($c in $CandidateSuffixes) {
        $full = "$Type/$c"
        $hit = $names | Where-Object { $_ -ieq $full } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

# ----------------------------------------------------------------------------------------------
#  5. SKU constraint discovery  (data-driven handler table; add a row to support a new type)
# ----------------------------------------------------------------------------------------------
# Each "simple" spec: a type whose deny rule is a single SKU field constrained to observed values.
$SimpleSkuSpecs = @(
    @{ Type = 'Microsoft.Compute/disks';                       Fetch = { param($rg) Get-AzDisk -ResourceGroupName $rg };                 Select = { param($r) $r.Sku.Name };  Candidates = @('sku.name') }
    @{ Type = 'Microsoft.Compute/virtualMachineScaleSets';     Fetch = { param($rg) Get-AzVmss -ResourceGroupName $rg };                 Select = { param($r) $r.Sku.Name };  Candidates = @('sku.name') }
    @{ Type = 'Microsoft.Web/serverfarms';                     Fetch = { param($rg) Get-AzAppServicePlan -ResourceGroupName $rg };       Select = { param($r) $r.Sku.Name };  Candidates = @('sku.name') }
    @{ Type = 'Microsoft.ContainerRegistry/registries';        Fetch = { param($rg) Get-AzContainerRegistry -ResourceGroupName $rg };    Select = { param($r) $r.SkuName };    Candidates = @('sku.name') }
    @{ Type = 'Microsoft.EventHub/namespaces';                 Fetch = { param($rg) Get-AzEventHubNamespace -ResourceGroupName $rg };    Select = { param($r) $r.Sku.Name };  Candidates = @('sku.name') }
    @{ Type = 'Microsoft.Network/applicationGateways';         Fetch = { param($rg) Get-AzApplicationGateway -ResourceGroupName $rg };   Select = { param($r) $r.Sku.Tier };  Candidates = @('sku.tier','sku.name') }
    @{ Type = 'Microsoft.Network/expressRouteCircuits';        Fetch = { param($rg) Get-AzExpressRouteCircuit -ResourceGroupName $rg };  Select = { param($r) $r.Sku.Tier };  Candidates = @('sku.tier') }
    @{ Type = 'Microsoft.CognitiveServices/accounts';          Fetch = { param($rg) Get-AzCognitiveServicesAccount -ResourceGroupName $rg }; Select = { param($r) $r.Sku.Name }; Candidates = @('sku.name') }
)

# Build one "{ allOf:[ {type equals T}, {not:{field alias in [values]}} ] }" deny block.
function New-SkuDenyBlock {
    param([string]$Type, [string]$AliasField, [string[]]$Values, [switch]$WithWriteAction)
    if (-not $AliasField -or -not $Values -or $Values.Count -eq 0) { return $null }
    $conds = @()
    if ($WithWriteAction) { $conds += [ordered]@{ source = 'action'; equals = "$Type/write" } }
    $conds += [ordered]@{ field = 'type'; equals = $Type }
    $conds += [ordered]@{ not = [ordered]@{ field = $AliasField; in = [string[]]$Values } }
    return [ordered]@{ allOf = $conds }
}

# Returns an array of anyOf deny-blocks (one per SKU-bearing type that was observed).
function Get-SkuDenyBlocks {
    param([string]$Rg, [string[]]$ObservedTypes)
    $blocks = @()

    # --- Virtual machines (bespoke: 4 image/size fields in one allOf-not) ---
    if ($ObservedTypes -contains 'Microsoft.Compute/virtualMachines') {
        try {
            $vms = @(Get-AzVM -ResourceGroupName $Rg -ErrorAction Stop)
            if ($vms) {
                $vmType = 'Microsoft.Compute/virtualMachines'
                $inner = @()
                $map = @(
                    @{ Cand = @('imageOffer');     Vals = Get-DistinctValues ($vms.StorageProfile.ImageReference.Offer) }
                    @{ Cand = @('imagePublisher'); Vals = Get-DistinctValues ($vms.StorageProfile.ImageReference.Publisher) }
                    @{ Cand = @('imageSku');       Vals = Get-DistinctValues ($vms.StorageProfile.ImageReference.Sku) }
                    @{ Cand = @('sku.name');       Vals = Get-DistinctValues ($vms.HardwareProfile.VmSize) }
                )
                foreach ($f in $map) {
                    $alias = Resolve-SkuAlias -Type $vmType -CandidateSuffixes $f.Cand
                    if ($alias -and $f.Vals.Count) {
                        $inner += [ordered]@{ field = $alias; in = [string[]]$f.Vals }
                    }
                }
                if ($inner.Count) {
                    $blocks += [ordered]@{
                        allOf = @(
                            [ordered]@{ field = 'type'; equals = $vmType },
                            [ordered]@{ not = [ordered]@{ allOf = $inner } }
                        )
                    }
                    Write-Good "VM size/image constraints captured ($($inner.Count) fields)."
                }
            }
        } catch { Write-Warn2 "VM scan skipped: $_" }
    }

    # --- Storage accounts (bespoke: gate on the write action) ---
    if ($ObservedTypes -contains 'Microsoft.Storage/storageAccounts') {
        try {
            $sa = @(Get-AzStorageAccount -ResourceGroupName $Rg -ErrorAction Stop)
            $vals = Get-DistinctValues ($sa | ForEach-Object { $_.Sku.Name })
            $alias = Resolve-SkuAlias -Type 'Microsoft.Storage/storageAccounts' -CandidateSuffixes @('sku.name')
            $b = New-SkuDenyBlock -Type 'Microsoft.Storage/storageAccounts' -AliasField $alias -Values $vals -WithWriteAction
            if ($b) { $blocks += $b ; Write-Good "Storage SKU constraint captured ($($vals -join ', '))." }
        } catch { Write-Warn2 "Storage scan skipped: $_" }
    }

    # --- SQL databases (bespoke: enumerate servers -> databases, ignore system DBs) ---
    if ($ObservedTypes -contains 'Microsoft.Sql/servers/databases' -or $ObservedTypes -contains 'Microsoft.Sql/servers') {
        try {
            $objectives = @()
            foreach ($srv in @(Get-AzSqlServer -ResourceGroupName $Rg -ErrorAction Stop)) {
                $dbs = @(Get-AzSqlDatabase -ResourceGroupName $Rg -ServerName $srv.ServerName -ErrorAction Stop |
                         Where-Object { $_.DatabaseName -ne 'master' })
                $objectives += $dbs | ForEach-Object { $_.CurrentServiceObjectiveName }
            }
            $vals  = Get-DistinctValues $objectives
            $alias = Resolve-SkuAlias -Type 'Microsoft.Sql/servers/databases' -CandidateSuffixes @('requestedServiceObjectiveName')
            $b = New-SkuDenyBlock -Type 'Microsoft.Sql/servers/databases' -AliasField $alias -Values $vals
            if ($b) { $blocks += $b ; Write-Good "SQL DB objective constraint captured ($($vals -join ', '))." }
        } catch { Write-Warn2 "SQL scan skipped: $_" }
    }

    # --- Key vaults (bespoke: per-vault Get to read the SKU) ---
    if ($ObservedTypes -contains 'Microsoft.KeyVault/vaults') {
        try {
            $skus = @()
            foreach ($kv in @(Get-AzKeyVault -ResourceGroupName $Rg -ErrorAction Stop)) {
                $full = Get-AzKeyVault -VaultName $kv.VaultName -ResourceGroupName $Rg -ErrorAction SilentlyContinue
                if ($full) { $skus += "$($full.Sku)" }
            }
            $vals  = Get-DistinctValues $skus
            $alias = Resolve-SkuAlias -Type 'Microsoft.KeyVault/vaults' -CandidateSuffixes @('sku.name')
            $b = New-SkuDenyBlock -Type 'Microsoft.KeyVault/vaults' -AliasField $alias -Values $vals
            if ($b) { $blocks += $b ; Write-Good "Key Vault SKU constraint captured ($($vals -join ', '))." }
        } catch { Write-Warn2 "Key Vault scan skipped: $_" }
    }

    # --- Simple single-field SKU types ---
    foreach ($spec in $SimpleSkuSpecs) {
        if ($ObservedTypes -notcontains $spec.Type) { continue }
        try {
            $items = @(& $spec.Fetch $Rg)
            if (-not $items) { continue }
            $vals  = Get-DistinctValues ($items | ForEach-Object { & $spec.Select $_ })
            $alias = Resolve-SkuAlias -Type $spec.Type -CandidateSuffixes $spec.Candidates
            $b = New-SkuDenyBlock -Type $spec.Type -AliasField $alias -Values $vals
            if ($b) { $blocks += $b ; Write-Good "$($spec.Type) SKU constraint captured ($($vals -join ', '))." }
        } catch { Write-Warn2 "$($spec.Type) scan skipped: $_" }
    }

    return $blocks
}

# ----------------------------------------------------------------------------------------------
#  6 & 7. Build RBAC role + deny policy objects
# ----------------------------------------------------------------------------------------------
function Build-RbacRole {
    param($Ctx, $Baseline, [string[]]$ObservedTypes)

    $providers = Get-DistinctValues ($ObservedTypes | ForEach-Object { ($_ -split '/')[0] })

    $actions = [System.Collections.Generic.List[string]]::new()
    foreach ($a in $Baseline.baseActions) { [void]$actions.Add($a) }
    foreach ($p in $providers) {
        $w = "$p/*"
        if (-not $actions.Contains($w)) { [void]$actions.Add($w) }
    }

    $dataActions = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $providers) {
        if ($Baseline.dataActionsByProvider.PSObject.Properties.Name -contains $p) {
            foreach ($d in $Baseline.dataActionsByProvider.$p) {
                if (-not $dataActions.Contains($d)) { [void]$dataActions.Add($d) }
            }
        }
    }

    $scopeTemplate = if ($SubstituteScope) { $Baseline.assignableScopeSubstituted } else { $Baseline.assignableScopePlaceholder }
    $scope = $scopeTemplate.
        Replace('{SubscriptionId}', $Ctx.SubscriptionId).
        Replace('{ResourceGroup}',  $Ctx.ResourceGroup)

    return [ordered]@{
        Name             = $Baseline.roleNamePattern.Replace('{LabName}', $Ctx.LabName)
        IsCustom         = $true
        Description      = $Baseline.descriptionPattern.Replace('{LabName}', $Ctx.LabName)
        Actions          = [string[]]$actions
        NotActions       = [string[]]$Baseline.notActions
        DataActions      = [string[]]$dataActions
        NotDataActions   = @()
        AssignableScopes = [string[]]@($scope)
    }
}

function Build-DenyPolicy {
    param([string[]]$ObservedTypes, $SkuDenyBlocks)

    # Allow-list: permit each observed type and its children; deny anything else.
    $allowConds = @()
    foreach ($t in $ObservedTypes) { $allowConds += [ordered]@{ field = 'type'; like = "$t/*" } }
    $allowConds += [ordered]@{ field = 'type'; in = [string[]]$ObservedTypes }
    $notAllowed = [ordered]@{ not = [ordered]@{ anyOf = $allowConds } }

    $anyOf = @($notAllowed)
    foreach ($b in $SkuDenyBlocks) { if ($b) { $anyOf += $b } }

    return [ordered]@{
        if   = [ordered]@{ anyOf = $anyOf }
        then = [ordered]@{ effect = 'deny' }
    }
}

# ----------------------------------------------------------------------------------------------
#  8. Output
# ----------------------------------------------------------------------------------------------
function Write-LabArtifacts {
    param($Ctx, $Role, $Policy)
    $dir = Join-Path $OutputRoot $Ctx.LabName
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $rolePath   = Join-Path $dir 'cust-rbac.json'
    $policyPath = Join-Path $dir 'custom-policy.json'

    # Windows PowerShell 5.1 ConvertTo-Json emits < > ' for < > ' (valid JSON,
    # but it breaks a literal find/replace on <SUBSCRIPTION_ID> and reads unlike the curated files).
    # Restore the readable characters; the result is still valid JSON. ($bs is a literal backslash
    # so the 6-char escape tokens are unambiguous.)
    function Format-Json([object]$Obj) {
        $bs = [char]92
        ($Obj | ConvertTo-Json -Depth 100).
            Replace("${bs}u003c", '<').Replace("${bs}u003e", '>').Replace("${bs}u0027", "'")
    }

    # Overwrite (never append) so re-runs are idempotent.
    Format-Json $Role   | Set-Content -Path $rolePath   -Encoding UTF8
    Format-Json $Policy | Set-Content -Path $policyPath -Encoding UTF8

    Write-Good "Wrote $rolePath"
    Write-Good "Wrote $policyPath"
    return @($rolePath, $policyPath)
}

# ----------------------------------------------------------------------------------------------
#  Main  (skipped when the file is dot-sourced, e.g. for unit testing the builders)
# ----------------------------------------------------------------------------------------------
if ($MyInvocation.InvocationName -eq '.') { return }

$transcript = $null
foreach ($logDir in @('C:\WindowsAzure\Logs', $env:TEMP)) {
    if (Test-Path $logDir) { $transcript = Join-Path $logDir 'Generate-RbacPolicy.log'; break }
}
if ($transcript) { try { Start-Transcript -Path $transcript -Append | Out-Null } catch {} }

try {
    if (-not (Test-Path $BaselinePath)) { throw "Baseline template not found: $BaselinePath" }
    $baseline = Get-Content $BaselinePath -Raw | ConvertFrom-Json

    $ctx = Resolve-LabContext
    Write-Host ''
    Write-Info  'Resolved context:'
    Write-Host  "    Subscription : $($ctx.SubscriptionId)"
    Write-Host  "    Tenant       : $($ctx.TenantId)"
    Write-Host  "    ResourceGroup: $($ctx.ResourceGroup)"
    Write-Host  "    DeploymentId : $($ctx.DeploymentId)"
    Write-Host  "    LabName      : $($ctx.LabName)"
    Write-Host  "    Auth         : $($ctx.AuthMethod)"
    Write-Host  "    Output dir   : $(Join-Path $OutputRoot $ctx.LabName)"
    Write-Host ''

    if ($DryRun) { Write-Warn2 'DryRun: stopping before any Azure call or file write.'; return }

    Connect-LabAzure -Ctx $ctx
    $types = Get-LabResourceTypes -Rg $ctx.ResourceGroup
    if (-not $types -or $types.Count -eq 0) { throw "No resources in '$($ctx.ResourceGroup)' - nothing to generate. Run after the lab is fully deployed." }

    $skuBlocks = Get-SkuDenyBlocks -Rg $ctx.ResourceGroup -ObservedTypes $types
    $role      = Build-RbacRole   -Ctx $ctx -Baseline $baseline -ObservedTypes $types
    $policy    = Build-DenyPolicy  -ObservedTypes $types -SkuDenyBlocks $skuBlocks

    $paths = Write-LabArtifacts -Ctx $ctx -Role $role -Policy $policy

    Write-Host ''
    Write-Good "Done. Review the two files, then apply with:"
    Write-Host  "    New-AzRoleDefinition -InputFile `"$($paths[0])`""
    Write-Host  "    New-AzPolicyDefinition -Name '$($ctx.LabName)-deny' -Policy `"$($paths[1])`" | New-AzPolicyAssignment -Scope <rg-id>"
}
catch {
    Write-Err $_.Exception.Message
    throw
}
finally {
    if ($transcript) { try { Stop-Transcript | Out-Null } catch {} }
}
