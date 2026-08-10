# Parameters - UserUPN | Get-AZUSER-UPN

# --- Pre-set variables ---
$tenantId     = $sysAddedTenantId
$skuId        = "5b631642-bd26-49fe-bd20-1daaa972ef80"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Power Apps Developer Plan Assignment" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# --- Authenticate using SPN ---
Write-Host "Authenticating with Service Principal..." -ForegroundColor Yellow

Import-Module -Name Microsoft.Graph.Authentication
Import-Module -Name Microsoft.Graph.Users

Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $Credential -NoWelcome

Write-Host "Authenticated successfully." -ForegroundColor Green
Write-Host ""

# --- Get User ID ---
Write-Host "Looking up user: $UserUPN" -ForegroundColor Yellow

$userId = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$UserUPN").id

Write-Host "User found: $userId" -ForegroundColor Green

# --- Assign License ---
Write-Host "Assigning Power Apps Developer Plan..." -ForegroundColor Yellow

Invoke-MgGraphRequest -Method POST `
    -Uri "https://graph.microsoft.com/v1.0/users/$userId/assignLicense" `
    -Body (@{ addLicenses = @(@{ skuId = $skuId }); removeLicenses = @() } | ConvertTo-Json -Depth 5) `
    -ContentType "application/json"

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  SUCCESS!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  User : $UserUPN" -ForegroundColor Green
Write-Host "  Plan : Power Apps Developer Plan" -ForegroundColor Green
Write-Host ""

Disconnect-MgGraph