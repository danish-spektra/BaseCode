Select-AzSubscription -SubscriptionId $subscriptionId
# Initialize an empty array to store deleted resources
$deletedOpenAireSource = @()

# Get the list of deleted resources
$deletedResources = Get-AzResource -ResourceId "/subscriptions/$subscriptionId/providers/Microsoft.CognitiveServices/deletedAccounts" -ApiVersion "2021-04-30"

# Check if there are resources available
if ($deletedResources) {
    # Loop through each deleted resource
    foreach ($resource in $deletedResources) {
        # Construct the resource ID for deletion
        $resourceId = "/subscriptions/$subscriptionId/providers/Microsoft.CognitiveServices/locations/$($resource.Location)/resourceGroups/$($resource.ResourceGroupName)/deletedAccounts/$($resource.ResourceName)"

        # Remove the resource
        Remove-AzResource -ResourceId $resourceId -ApiVersion "2021-04-30" -Force

        # Add the deleted resource to the array
        $deletedOpenAireSource += $resource
    }

    # Output the deleted resources if needed
    $deletedOpenAireSource
} else {
    Write-Host "No deleted resources found."
}


# Parameters
# subscriptionId -> GET-SUBSCRIPTION