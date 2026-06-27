# User email to process
$UserEmail = $UserUPN
             
$GroupId = "bb0215fb-69d3-4d16-be56-cd2da619de31"  
$TenantId = "f871d17e-efcd-44c7-ba5a-0162efa2fded"              
$ClientId = "e6b585c6-079f-489c-ae6b-a57a274139ea"              
$ClientSecret = "<YOUR_CLIENT_SECRET>"
 
# Connect to Microsoft Graph
$securePassword = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ClientId, $securePassword
Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome
Write-Host "Connected to Microsoft Graph API"

# Variable to store invited user ID for synchronization
$invitedUserId = $null

# Process the user email and send invitation
Write-Host "Processing user: $UserEmail"

try {
    $params = @{
        InvitedUserEmailAddress = $UserEmail
        SendInvitationMessage = $true
    }
    $invitation = New-MgInvitation @params -InviteRedirectUrl "https://myapplications.microsoft.com/?tenantid=f871d17e-efcd-44c7-ba5a-0162efa2fded" -verbose
    Write-Host "Invitation sent to $UserEmail" -ForegroundColor Green
    
    # Add user to group
    New-MgGroupMember -GroupId $GroupId -DirectoryObjectId $invitation.InvitedUser.Id
    Write-Host "User $UserEmail added to group" -ForegroundColor Green
    
    # Store user ID for synchronization
    $invitedUserId = $invitation.InvitedUser.Id
}
catch {
    Write-Host "Failed to process user $UserEmail : $($_.Exception.Message)" -ForegroundColor Red
}
 
 
 
$app_name = "GitHub Enterprise Managed User"
# Get the user to assign, and the service principal for the app to assign to
$sp = Get-MgServicePrincipal -Filter "displayName eq '$app_name'"
$appRoleid = "27d9891d-2c17-4f45-a262-781a0e55c80a"

# Perform synchronization for the user
if ($invitedUserId) {
    Write-Host "Starting synchronization for user..."
    
    $params = @{
        parameters = @(
            @{
                ruleId = "03f7d90d-bf71-41b1-bda6-aaf0ddbee5d8"
                subjects = @(
                    @{
                        objectId = "bb0215fb-69d3-4d16-be56-cd2da619de31"
                        objectTypeName = "Group"
                        links = @{
                            members = @(
                                @{
                                    objectId = $invitedUserId
                                    objectTypeName = "User"
                                }
                            )
                        }
                    }
                )
            }
        )
    }
     
    try {
        New-MgServicePrincipalSynchronizationJobOnDemand -ServicePrincipalId da6c7f14-b7a5-4b1b-b357-3594173bea4a -SynchronizationJobId gitHubEnterpriseCloud.f871d17eefcd44c7ba5a0162efa2fded.d2318294-74b6-4d39-b351-8f0ee74687c0 -BodyParameter $params  2>$null
        Write-Host "Synchronization job initiated successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to initiate synchronization: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "No user to synchronize" -ForegroundColor Yellow
}

Write-Host "Script completed. Processed user: $UserEmail" -ForegroundColor Cyan