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

# Modifying choco target package to 'python' fetches the newest major stable release
choco install python -y
choco install vscode -y

Stop-Transcript
 
Restart-Computer -Force