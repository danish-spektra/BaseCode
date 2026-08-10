# --- Pre-set variables ---
# sku.capacity is in units of 1,000 tokens-per-minute (TPM).
# 10 = 10K TPM  ->  max ~4.8M tokens over an 8-hour lab. Raise per-lab if needed.
$maxTokenCapacity = 10
$policyName       = "restrict-aifoundry-tokens"
$apiVersion       = "2024-10-01"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  AI Foundry Token Usage Restriction" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# --- Authenticate ---
Write-Host "Authenticating to Azure..." -ForegroundColor Yellow

if (Test-Path 'C:\LabFiles\AzureCreds.ps1') { . 'C:\LabFiles\AzureCreds.ps1' }

$securePassword = ConvertTo-SecureString $AzurePassword -AsPlainText -Force
$credential     = New-Object System.Management.Automation.PSCredential($AzureUserName, $securePassword)
Connect-AzAccount -Credential $credential -TenantId $AzureTenantID -Subscription $AzureSubscriptionID | Out-Null
$subscriptionId = (Get-AzContext).Subscription.Id

Write-Host "Authenticated. Subscription: $subscriptionId" -ForegroundColor Green
Write-Host ""

# --- Cap existing model deployments ---
Write-Host "Scanning AI Foundry / Cognitive Services accounts..." -ForegroundColor Yellow

$accounts = Get-AzResource -ResourceType "Microsoft.CognitiveServices/accounts"

foreach ($account in $accounts) {
    Write-Host "Account: $($account.Name)" -ForegroundColor Cyan

    $response    = Invoke-AzRestMethod -Method GET -Path "$($account.Id)/deployments?api-version=$apiVersion"
    $deployments = ($response.Content | ConvertFrom-Json).value

    foreach ($deployment in $deployments) {
        $capacity = $deployment.sku.capacity
        if ($capacity -gt $maxTokenCapacity) {
            Write-Host "  $($deployment.name): capacity $capacity -> $maxTokenCapacity" -ForegroundColor Yellow
            $payload = @{ sku = @{ name = $deployment.sku.name; capacity = $maxTokenCapacity } } | ConvertTo-Json -Depth 5
            $patch   = Invoke-AzRestMethod -Method PATCH -Path "$($account.Id)/deployments/$($deployment.name)?api-version=$apiVersion" -Payload $payload
            if ($patch.StatusCode -ge 300) {
                Write-Host "  FAILED to cap $($deployment.name): $($patch.Content)" -ForegroundColor Red
            }
        } else {
            Write-Host "  $($deployment.name): capacity $capacity (within limit)" -ForegroundColor Green
        }
    }
}
Write-Host ""

# --- Create & assign deny policy ---
# Denies: new Foundry (Cognitive Services) accounts/projects, and model deployments
# above the token capacity limit. Repo copy: Labs-permissions/Policies/Generic/foundry-restrict.json
Write-Host "Assigning deny policy '$policyName'..." -ForegroundColor Yellow

$policyRule = @'
{
  "if": {
    "anyOf": [
      {
        "field": "type",
        "in": [
          "Microsoft.CognitiveServices/accounts",
          "Microsoft.CognitiveServices/accounts/projects"
        ]
      },
      {
        "allOf": [
          {
            "field": "type",
            "equals": "Microsoft.CognitiveServices/accounts/deployments"
          },
          {
            "field": "Microsoft.CognitiveServices/accounts/deployments/sku.capacity",
            "greater": "[parameters('maxTokenCapacity')]"
          }
        ]
      }
    ]
  },
  "then": {
    "effect": "deny"
  }
}
'@

$policyParameters = @'
{
  "maxTokenCapacity": {
    "type": "Integer",
    "metadata": {
      "description": "Maximum sku.capacity (1 unit = 1K TPM) allowed on a model deployment",
      "displayName": "Max token capacity"
    },
    "defaultValue": 10
  }
}
'@

$definition = New-AzPolicyDefinition -Name $policyName `
    -DisplayName "Restrict AI Foundry deployments and token capacity" `
    -Description "Denies creation of new AI Foundry (Cognitive Services) accounts/projects and caps model deployment token capacity. Foundry resources must be pre-deployed by CloudLabs." `
    -Policy $policyRule -Parameter $policyParameters -Mode Indexed

New-AzPolicyAssignment -Name $policyName -Scope "/subscriptions/$subscriptionId" `
    -PolicyDefinition $definition -PolicyParameterObject @{ maxTokenCapacity = $maxTokenCapacity } | Out-Null

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  SUCCESS!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Deployments capped at : $maxTokenCapacity K TPM" -ForegroundColor Green
Write-Host "  Policy assigned       : $policyName" -ForegroundColor Green
Write-Host ""
