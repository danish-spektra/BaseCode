$count = 0
$foundWorkspace = $false
$foundReport = $false
$sub = $subscriptionid
$did = $deploymentid

# Fabric workspace naming convention for this lab
$workspaceName = "fabric-workspace-$did"
$reportName    = "Contoso-Flight-Loyalty-Dashboard"

do
{
    $count++
    try
    {
        Set-AzContext -Subscription $sub | Out-Null
        Write-Host "Searching Fabric Workspace : $workspaceName"
        Write-Host "Searching Report           : $reportName"

        # Acquire Fabric REST API token (Az.Accounts >= 12 returns SecureString)
        $tokenObj = Get-AzAccessToken -ResourceUrl 'https://api.fabric.microsoft.com' -AsSecureString -ErrorAction SilentlyContinue
        if (-not $tokenObj)
        {
            $tokenObj = Get-AzAccessToken -ResourceUrl 'https://api.fabric.microsoft.com'
        }
        if (-not $tokenObj -or -not $tokenObj.Token)
        {
            throw "Failed to acquire access token for the Fabric REST API."
        }

        if ($tokenObj.Token -is [System.Security.SecureString])
        {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenObj.Token)
            try   { $accessToken = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
            finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        }
        else
        {
            $accessToken = [string]$tokenObj.Token
        }

        $headers = @{
            Authorization = "Bearer $accessToken"
            Accept        = 'application/json'
        }

        # Resolve workspace by display name (trim to tolerate stray whitespace in Fabric names)
        $workspacesResp = Invoke-RestMethod -Method GET -Uri 'https://api.fabric.microsoft.com/v1/workspaces' -Headers $headers
        $workspace = $workspacesResp.value |
            Where-Object { $_.displayName.Trim() -eq $workspaceName.Trim() } |
            Select-Object -First 1

        if (!$workspace)
        {
            $message = @{
                Status  = "Failed"
                Message = "Fabric workspace '$workspaceName' was not found or the signed-in identity does not have access. Please complete the workspace creation task."
            } | ConvertTo-Json
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::OK
                Body = $message
            })
            return
        }

        $foundWorkspace = $true
        Write-Host "Workspace found. Id: $($workspace.id)"

        # List reports in the workspace
        $reportsUri  = "https://api.fabric.microsoft.com/v1/workspaces/$($workspace.id)/reports"
        $reportsResp = Invoke-RestMethod -Method GET -Uri $reportsUri -Headers $headers
        $reports     = @($reportsResp.value)

        foreach ($report in $reports)
        {
            Write-Host "Report : $($report.displayName)"
            if ($report.displayName.Trim() -eq $reportName.Trim())
            {
                $foundReport = $true
            }
        }

        if ($foundWorkspace -and $foundReport)
        {
            $message = @{
                Status  = "Succeeded"
                Message = "Report '$reportName' was found in workspace '$workspaceName'."
            } | ConvertTo-Json
        }
        else
        {
            $message = @{
                Status  = "Failed"
                Message = "Report '$reportName' was not found in workspace '$workspaceName'. Please complete the task to create the report."
            } | ConvertTo-Json
        }

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::OK
            Body = $message
        })
        return
    }
    catch
    {
        if ($count -ge 3)
        {
            $message = @{
                Status  = "Failed"
                Message = $_.Exception.Message
            } | ConvertTo-Json
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::OK
                Body = $message
            })
            return
        }
        Start-Sleep -Seconds 5
    }
} while ($count -lt 3)