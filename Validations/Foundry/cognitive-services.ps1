$count = 0
$sub = $subscriptionid
$did = $deploymentid          # CloudLabs Deployment ID
$cloudDid = $clouddid         # Optional if available
 
# Resource Group naming convention (static for this lab)
$resourceGroupName = "LabVM"
 
# Foundry account naming convention (dynamic per deployment)
$foundryAccountName = "openai-lab-$did"
 
do
{
    $count++
    try
    {
        Set-AzContext -Subscription $sub | Out-Null
        Write-Host "Searching Resource Group: $resourceGroupName"
 
        # Check Resource Group
        $rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
        if (!$rg)
        {
            $message = @{
                Status  = "Failed"
                Message = "Resource Group '$resourceGroupName' not found."
            } | ConvertTo-Json
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::OK
                Body = $message
            })
            return
        }
 
        # Look up the specific Foundry account by name
        Write-Host "Searching for Foundry account: $foundryAccountName"
        $openAIAccount = Get-AzResource -ResourceGroupName $resourceGroupName `
            -ResourceType "Microsoft.CognitiveServices/accounts" `
            -Name $foundryAccountName -ErrorAction SilentlyContinue
 
        if (!$openAIAccount)
        {
            $message = @{
                Status  = "Failed"
                Message = "Foundry account '$foundryAccountName' was not found in resource group '$resourceGroupName'."
            } | ConvertTo-Json
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::OK
                Body = $message
            })
            return
        }
 
        Write-Host "Cognitive Services Resource : $($openAIAccount.Name)"
        Write-Host "Resource Kind              : $($openAIAccount.Kind)"
 
        # Foundry resources may still be exposed with OpenAI/AIServices kinds in some environments.
        if ($openAIAccount.Kind -notin @("Foundry", "OpenAI", "AIServices"))
        {
            $message = @{
                Status  = "Failed"
                Message = "Resource '$foundryAccountName' was found but its Kind ('$($openAIAccount.Kind)') is not a recognized Foundry/OpenAI kind."
            } | ConvertTo-Json
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::OK
                Body = $message
            })
            return
        }
 
        # Foundry resource exists and is of a valid kind - validation succeeds
        $message = @{
            Status  = "Succeeded"
            Message = "Foundry resource '$foundryAccountName' was found in resource group '$resourceGroupName'."
        } | ConvertTo-Json
 
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::OK
            Body = $message
        })
        return
    }
    catch
    {
        if($count -ge 3)
        {
            $message = @{
                Status = "Failed"
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
} while($count -lt 3)