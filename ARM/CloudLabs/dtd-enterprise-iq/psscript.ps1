Param (
    [Parameter(Mandatory = $true)]
    [string]
    $AzureUserName,
    [string]
    $AzurePassword,
    [string]
    $AzureTenantID,
    [string]
    $AzureSubscriptionID,
    [string]
    $ODLID,
    [string]
    $DeploymentID,
    [string]
    $adminUsername,
    [string]
    $adminPassword,
    [string]
    $trainerUserName,
    [string]
    $trainerUserPassword
)
 
Start-Transcript -Path C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt -Append
[Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls" 

#Import Common Functions
$path = pwd
$path=$path.Path
$commonscriptpath = "$path" + "\cloudlabs-common\cloudlabs-windows-functions.ps1"
. $commonscriptpath
 
# Run Imported functions from cloudlabs-windows-functions.ps1
WindowsServerCommon

InstallAzCLI
InstallAzPowerShellModule
InstallModernVmValidator

CreateCredFile $AzureUserName $AzurePassword $AzureTenantID $AzureSubscriptionID $DeploymentID 

Enable-CloudLabsEmbeddedShadow $adminUsername $trainerUserName $trainerUserPassword

choco install python312 -y

Write-Log "Creating dataset folder and downloading lab files..."
$datasetPath = "C:\dataset"
$tempPath    = "C:\Temp"

# Ensure directories exist
New-Item -ItemType Directory -Force -Path $datasetPath | Out-Null
New-Item -ItemType Directory -Force -Path $tempPath | Out-Null

# Direct URL
New-Item -ItemType Directory -Force -Path $datasetPath | Out-Null
New-Item -ItemType Directory -Force -Path $tempPath | Out-Null

$zipUrl  = "https://github.com/CloudLabsAI-Azure/hack-in-a-day-data/archive/refs/heads/enterprise-iq3.zip"
$zipPath = "$tempPath\labfiles.zip"

Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

Expand-Archive -Path $zipPath -DestinationPath $tempPath -Force

Get-ChildItem -Path "$tempPath\hack-in-a-day-data-enterprise-iq3\*" |
Move-Item -Destination $datasetPath -Force

Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Remove-Item "$tempPath\hack-in-a-day-data-enterprise-iq3" -Recurse -Force -ErrorAction SilentlyContinue

Write-Log "CSV files extracted and organized in $datasetPath successfully."

Stop-Transcript
 
Restart-Computer -Force