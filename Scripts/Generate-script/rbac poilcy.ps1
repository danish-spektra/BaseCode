# For the Script u need - rg-name, subscription id, odl id (AAD Domain), tap password. 

Login-AzureRmAccount
Get-AzureRMSubscription
$subscriptionID = "de0d3730-3fc5-47e9-b578-4dedd476498d"
Select-AzureRmSubscription -Subscription $subscriptionID

    $rbacName = "Spektra Custom RBAC"
	<# Name you provide in $rbacName will be written in Rbac name field as shown below
	{
	  "Name": "Custom RBAC Name",
	  "Id": null,#>

	# Below Command will write the console output in a text file
	Start-Transcript -Path C:\Rbac-Policy\Policy\rawdata\rawdata.txt -Append

    <#----------------------------------------------------------------------------#>
	Function createDirectory{
	  New-Item -ItemType directory -Path C:\Rbac-Policy\Rbac\
	} createDirectory
	<#----------------------------------------------------------------------------#>


	Function RGsOneByOne {
	# Below two commands are there to get the RGs. One is added as comment and one executable.
	# If you want Rbac for particular RGs then add TagName and TagValue for those particular RGs. 

$RGs = "SmartHotelRG"
	# $RGs = Get-AzureRMResourceGroup

	# $TagName = "Enter Tag name of RG here"
	# $TagValue = "Enter Tag value of RG here"
	# $RGs = Get-AzureRMResourceGroup -Tag @{ "$TagName"=$TagValue }

	foreach($RG in $RGs)
	{ 

        $RGName = $RG
	    Write-Host "======================================================="
	    Write-Host "Resource Group Name :" $RGName
	    Write-Host "======================================================="
		$resources = Get-AzureRmResource -oDataQuery "`$filter=resourcegroup eq '$RGName'"

        $exactResources = @()
        $resourceTypesForRbac = @()
        $resourceTypesForPolicy = @()
        $exactResources1 = @()
        $resourceTypesForRbac1 = @()
        $resourceTypesForPolicy1 = @()

        # Defult actions required in an RBAC file
        $resourceTypesForRbac += '"Microsoft.Authorization/*/read",'
        $resourceTypesForRbac += '"Microsoft.Resources/deployments/*",'
        $resourceTypesForRbac += '"Microsoft.Resources/subscriptions/resourceGroups/read",'
        

	# Find unique set of ResourceType
        foreach($resource in $resources) 
		{   
            $resource.ResourceType
            $resourceTypesForRbac += '"' + $resource.ResourceType + "/*" + '",'
            $resourceTypesForPolicy += $resource.ResourceType + "/*"
            $exactResources += '"' + $resource.ResourceType + '",'
		}

		$resourceTypesForPolicy1 += $resourceTypesForPolicy | select -uniq | Sort-Object

        $resourceTypesForRbac1 += $resourceTypesForRbac | select -uniq | Sort-Object
        $resourceTypesForRbac1.SetValue($resourceTypesForRbac1.GetValue($resourceTypesForRbac1.Length-1) -replace ".$", $resourceTypesForRbac1.Length-1)

        $exactResources1 += $exactResources | select -uniq | Sort-Object
        $exactResources1.SetValue($exactResources1.GetValue($exactResources1.Length-1) -replace ".$", $exactResources1.Length-1)

	<#-----------------------------------------------------------------------------------------------------------------------------------------#>

      # Storage Account
	  $storageAccounts = Get-AzureRmStorageAccount -ResourceGroupName $RGName
	  if($storageAccounts)
		  {
            $storageSKUArray = @()
            $storageSKUArray1 = @()
			foreach($storageAccount in $storageAccounts) 
			{  
                $storageSKUArray += '"' + $storageAccount.Sku.name + '",'
			}  

            $storageSKUArray1 += $storageSKUArray | select -uniq | Sort-Object
            $storageSKUArray1.SetValue($storageSKUArray1.GetValue($storageSKUArray1.Length-1) -replace ".$", $storageSKUArray1.Length-1)
		  }
	<#-----------------------------------------------------------------------------------------------------------------------------------------#>

      # Virtual Machine
	  $VMs = Get-AzureRMVM –ResourceGroupName $RGName
		if($VMs)
		{
            $vmSizeArray = @()
            $vmImagePublisherArray = @()
            $vmImageOfferArray = @()
            $vmImageSkuArray = @()
            $vmSizeArray1 = @()
            $vmImagePublisherArray1 = @()
            $vmImageOfferArray1 = @()
            $vmImageSkuArray1 = @()
			foreach($VM in $VMs) 
			{  
				$vmSizeArray += '"' + $VM.HardwareProfile.Vmsize + '",'
				$vmImagePublisherArray += '"' + $VM.StorageProfile.ImageReference.Publisher + '",'
				$vmImageOfferArray += '"' + $VM.StorageProfile.ImageReference.Offer + '",'
				$vmImageSkuArray += '"' + $VM.StorageProfile.ImageReference.Sku + '",'
			}
            
            $vmSizeArray1 += $vmSizeArray | select -uniq | Sort-Object
            $vmSizeArray1.SetValue($vmSizeArray1.GetValue($vmSizeArray1.Length-1) -replace ".$", $vmSizeArray1.Length-1)

            $vmImagePublisherArray1 += $vmImagePublisherArray | select -uniq | Sort-Object
            $vmImagePublisherArray1.SetValue($vmImagePublisherArray1.GetValue($vmImagePublisherArray1.Length-1) -replace ".$", $vmImagePublisherArray1.Length-1)

            $vmImageOfferArray1 += $vmImageOfferArray | select -uniq | Sort-Object
            $vmImageOfferArray1.SetValue($vmImageOfferArray1.GetValue($vmImageOfferArray1.Length-1) -replace ".$", $vmImageOfferArray1.Length-1)

            $vmImageSkuArray1 += $vmImageSkuArray | select -uniq | Sort-Object
            $vmImageSkuArray1.SetValue($vmImageSkuArray1.GetValue($vmImageSkuArray1.Length-1) -replace ".$", $vmImageSkuArray1.Length-1)
		}       
	<#-----------------------------------------------------------------------------------------------------------------------------------------#>
	  
      # SQL Server/DB
      $sqlDatabases = $null
      $sqlServers = Get-AzureRmSqlServer -ResourceGroupName $RGName
	  if($sqlServers)
	  {
        $sqlServerVersionsArray = @()
        $sqlDBEditionArray = @()
        $sqlDBObjectiveIdArray = @()
        $sqlDBServiceObjectiveNameArray = @()
        $sqlServerVersionsArray1 = @()
        $sqlDBEditionArray1 = @()
        $sqlDBObjectiveIdArray1 = @()
        $sqlDBServiceObjectiveNameArray1 = @()
		foreach($sqlServer in $sqlServers) 
	    { 
			$sqlServerName = $sqlServer.ServerName
		    $sqlServerVersionsArray += '"' + $sqlServers.ServerVersion + '",'
			$sqlDatabases = Get-AzureRmSqlDatabase -ResourceGroupName $RGName -ServerName $sqlServerName
			if($sqlDatabases)
		    {
				foreach($sqlDatabase in $sqlDatabases) 
				{ 
					$sqlDBEditionArray += '"' + $sqlDatabase.Edition + '",'
                    $sqlDBObjectiveIdArray += '"' + $sqlDatabase.CurrentServiceObjectiveId + '",'
					$sqlDBServiceObjectiveNameArray += '"' + $sqlDatabase.CurrentServiceObjectiveName + '",'
				}
			}	
	    }

		$sqlServerVersionsArray1 += $sqlServerVersionsArray | select -uniq | Sort-Object
        $sqlServerVersionsArray1.SetValue($sqlServerVersionsArray1.GetValue($sqlServerVersionsArray1.Length-1) -replace ".$", $sqlServerVersionsArray1.Length-1)

        $sqlDBEditionArray1 += $sqlDBEditionArray | select -uniq | Sort-Object
        $sqlDBEditionArray1.SetValue($sqlDBEditionArray1.GetValue($sqlDBEditionArray1.Length-1) -replace ".$", $sqlDBEditionArray1.Length-1)

        $sqlDBObjectiveIdArray1 += $sqlDBObjectiveIdArray | select -uniq | Sort-Object
        $sqlDBObjectiveIdArray1.SetValue($sqlDBObjectiveIdArray1.GetValue($sqlDBObjectiveIdArray1.Length-1) -replace ".$", $sqlDBObjectiveIdArray1.Length-1)

        $sqlDBServiceObjectiveNameArray1 += $sqlDBServiceObjectiveNameArray | select -uniq | Sort-Object
        $sqlDBServiceObjectiveNameArray1.SetValue($sqlDBServiceObjectiveNameArray1.GetValue($sqlDBServiceObjectiveNameArray1.Length-1) -replace ".$", $sqlDBServiceObjectiveNameArray1.Length-1)
	  }

	<#-----------------------------------------------------------------------------------------------------------------------------------------#>

      # App Service Plan
	  $appServicePlans = Get-AzureRmAppServicePlan -ResourceGroupName $RGName
	  if($appServicePlans)
		{
          $appServicePlanSKUNameArray = @()
          $appServicePlanSKUTierArray = @()
          $appServicePlanSKUNameArray1 = @()
          $appServicePlanSKUTierArray1 = @()
		  foreach($appServicePlan in $appServicePlans) 
		  { 
			  $appServicePlanSKUNameArray += '"' + $appServicePlan.Sku.name + '",'
              $appServicePlanSKUTierArray += '"' + $appServicePlan.Sku.Tier + '",'
		  }
		  
          $appServicePlanSKUNameArray1 += $appServicePlanSKUNameArray | select -uniq | Sort-Object
          $appServicePlanSKUNameArray1.SetValue($appServicePlanSKUNameArray1.GetValue($appServicePlanSKUNameArray1.Length-1) -replace ".$", $appServicePlanSKUNameArray1.Length-1)

          $appServicePlanSKUTierArray1 += $appServicePlanSKUTierArray | select -uniq | Sort-Object
          $appServicePlanSKUTierArray1.SetValue($appServicePlanSKUTierArray1.GetValue($appServicePlanSKUTierArray1.Length-1) -replace ".$", $appServicePlanSKUTierArray1.Length-1)
		}
	<#-----------------------------------------------------------------------------------------------------------------------------------------#>
    
    # VM Scale Set
    $vmScaleSets = Get-AzureRmVmss -ResourceGroupName $RGName
	  if($vmScaleSets)
		  {
            $vmScaleSetSKUNameArray = @()
            $vmScaleSetSKUTierArray = @()
            $vmScaleSetSKUNameArray1 = @()
            $vmScaleSetSKUTierArray1 = @()
			foreach($vmScaleSet in $vmScaleSets) 
			{  
                $vmScaleSetSKUNameArray += '"' + $vmScaleSet.Sku.name + '",'
                $vmScaleSetSKUTierArray += '"' + $vmScaleSet.Sku.Tier + '",'
			}  

            $vmScaleSetSKUNameArray1 += $vmScaleSetSKUNameArray | select -uniq | Sort-Object
            $vmScaleSetSKUNameArray1.SetValue($vmScaleSetSKUNameArray1.GetValue($vmScaleSetSKUNameArray1.Length-1) -replace ".$", $vmScaleSetSKUNameArray1.Length-1)

            $vmScaleSetSKUTierArray1 += $vmScaleSetSKUTierArray | select -uniq | Sort-Object
            $vmScaleSetSKUTierArray1.SetValue($vmScaleSetSKUTierArray1.GetValue($vmScaleSetSKUTierArray1.Length-1) -replace ".$", $vmScaleSetSKUTierArray1.Length-1)
		  }

    <#-----------------------------------------------------------------------------------------------------------------------------------------#>
    
    # Disk
    $disks = Get-AzureRmDisk -ResourceGroupName $RGName
	  if($disks)
		  {
            $diskSKUNameArray = @()
            $diskSKUTierArray = @()
            $diskSKUNameArray1 = @()
            $diskSKUTierArray1 = @()
			foreach($disk in $disks) 
			{  
                $diskSKUNameArray += '"' + $disk.Sku.name + '",'
                $diskSKUTierArray += '"' + $disk.Sku.Tier + '",'
			}  

            $diskSKUNameArray1 += $diskSKUNameArray | select -uniq | Sort-Object
            $diskSKUNameArray1.SetValue($diskSKUNameArray1.GetValue($diskSKUNameArray1.Length-1) -replace ".$", $diskSKUNameArray1.Length-1)

            $diskSKUTierArray1 += $diskSKUTierArray | select -uniq | Sort-Object
            $diskSKUTierArray1.SetValue($diskSKUTierArray1.GetValue($diskSKUTierArray1.Length-1) -replace ".$", $diskSKUTierArray1.Length-1)
		  }

    <#-----------------------------------------------------------------------------------------------------------------------------------------#>
    
    # Load Balancer
    $lbs = Get-AzureRmLoadBalancer -ResourceGroupName $RGName
	  if($lbs)
		  {
            $lbSKUNameArray = @()
            $lbSKUNameArray1 = @()
			foreach($lb in $lbs) 
			{  
                $lbSKUNameArray += '"' + $lb.Sku.name + '",'
			}  

            $lbSKUNameArray1 += $lbSKUNameArray | select -uniq | Sort-Object
            $lbSKUNameArray1.SetValue($lbSKUNameArray1.GetValue($lbSKUNameArray1.Length-1) -replace ".$", $lbSKUNameArray1.Length-1)
		  }

    <#-----------------------------------------------------------------------------------------------------------------------------------------#>
    
    # Application Gateway
    $appGateways = Get-AzureRmApplicationGateway -ResourceGroupName $RGName
	  if($appGateways)
		  {
            $appGatewaySKUTierArray = @()
            $appGatewaySKUTierArray1 = @()
			foreach($appGateway in $appGateways) 
			{  
                $appGatewaySKUTierArray += '"' + $appGateway.Sku.Tier + '",'
			}  

            $appGatewaySKUTierArray1 += $appGatewaySKUTierArray | select -uniq | Sort-Object
            $appGatewaySKUTierArray1.SetValue($appGatewaySKUTierArray1.GetValue($appGatewaySKUTierArray1.Length-1) -replace ".$", $appGatewaySKUTierArray1.Length-1)
		  }

    <#-----------------------------------------------------------------------------------------------------------------------------------------#>
    
    # Express Route Circuit
    $expressRoutes = Get-AzureRmExpressRouteCircuit -ResourceGroupName $RGName
	  if($expressRoutes)
		  {
            $expressRoutesSKUTierArray = @()
            $expressRoutesSKUTierArray1 = @()
			foreach($expressRoute in $expressRoutes) 
			{  
                $expressRoutesSKUTierArray += '"' + $expressRoute.Sku.Tier + '",'
			}  

            $expressRoutesSKUTierArray1 += $expressRoutesSKUTierArray | select -uniq | Sort-Object
            $expressRoutesSKUTierArray1.SetValue($expressRoutesSKUTierArray1.GetValue($expressRoutesSKUTierArray1.Length-1) -replace ".$", $expressRoutesSKUTierArray1.Length-1)
		  }

    <#-----------------------------------------------------------------------------------------------------------------------------------------#>
    
    # Cognitive Services
    $cognitiveServiceAccounts = Get-AzureRmCognitiveServicesAccount -ResourceGroupName $RGName
    if($cognitiveServiceAccounts)
    {
        $cognativeServicesSKUArray = @()
        $cognativeServicesSKUArray1 = @()
        foreach($cognitiveServiceAccount in $cognitiveServiceAccounts) 
	    {  
            $cognativeServicesSKUArray += '"' + $cognitiveServiceAccount.Sku.Name + '",'
	    }

        $cognativeServicesSKUArray1 += $cognativeServicesSKUArray | select -uniq | Sort-Object
        $cognativeServicesSKUArray1.SetValue($cognativeServicesSKUArray1.GetValue($cognativeServicesSKUArray1.Length-1) -replace ".$", $cognativeServicesSKUArray1.Length-1)
    }

    <#-----------------------------------------------------------------------------------------------------------------------------------------#>
    
    # Container Registry
    $containerRegistries = Get-AzureRmContainerRegistry -ResourceGroupName $RGName
    if($containerRegistries)
    {
        $containerRegistrySKUArray = @()
        $containerRegistrySKUArray1 = @()
        foreach($containerRegistry in $containerRegistries) 
	    {  
            $containerRegistrySKUArray += '"' + $containerRegistry.SkuName + '",'
	    }

        $containerRegistrySKUArray1 += $containerRegistrySKUArray | select -uniq | Sort-Object
        $containerRegistrySKUArray1.SetValue($containerRegistrySKUArray1.GetValue($containerRegistrySKUArray1.Length-1) -replace ".$", $containerRegistrySKUArray1.Length-1)
    }

    <#-----------------------------------------------------------------------------------------------------------------------------------------#>
    
    # Key Vaults
    $keyVaults = Get-AzureRmKeyVault
    if($keyVaults)
    {
        $keyVaultSKUArray = @()
        $keyVaultSKUArray1 = @()
        foreach($keyVault in $keyVaults) 
	    {  
            $currentKeyVault = Get-AzureRMKeyVault -VaultName $keyVault.VaultName
            $keyVaultSKUArray += '"' + $currentKeyVault.SKU + '",'
	    }

        $keyVaultSKUArray1 += $keyVaultSKUArray | select -uniq | Sort-Object
        $keyVaultSKUArray1.SetValue($keyVaultSKUArray1.GetValue($keyVaultSKUArray1.Length-1) -replace ".$", $keyVaultSKUArray1.Length-1)
    }

     <#-----------------------------------------------------------------------------------------------------------------------------------------#>
    
    # Event Hub
    $eventHubs = Get-AzureRmEventHubNamespace -ResourceGroupName $RGName 
    if($eventHubs)
    {
        $eventHubSKUArray = @()
        $eventHubSKUArray1 = @()
        foreach($eventHub in $eventHubs) 
	    {  
            $eventHubSKUArray += '"' + $eventHub.Sku.Name + '",'
	    }

        $eventHubSKUArray1 += $eventHubSKUArray | select -uniq | Sort-Object
        $eventHubSKUArray1.SetValue($eventHubSKUArray1.GetValue($eventHubSKUArray1.Length-1) -replace ".$", $eventHubSKUArray1.Length-1)
    }

	<#-----------------------------------------------------------------------------------------------------------------------------------------#>
	Function policy {
	Param(
	[switch]$Passthru
	)
	if($Passthru){
	'{
	 "if": {
	    "anyOf": [
		 {
			"not": {
			  "anyOf": ['
			    for ($i=0; $i –le $resourceTypesForPolicy1.Length-1; $i++)
			    { '                    {
				    "field": "type",
				    "like": "' + $resourceTypesForPolicy1[$i] + '"
				    },'
			    }
                    '                    {
				    "field": "type",
				    "in": ['+"$exactResources1"+']
				    }
                ]
			}
		 },'

      <#-----------------------------------------------------------------------------------------------------------------------------------------#>
	  if($disks)
		{
		'          {
		  "allof": [
			{
			  "field": "type",
			  "equals": "Microsoft.Compute/disks"
			},
			{
			  "not": {
				"field": "Microsoft.Compute/disks/Sku.Tier",
				"in": ['+"$diskSKUTierArray1"+']
				}
			  }
			]
		  },'
		}

      <#-----------------------------------------------------------------------------------------------------------------------------------------#>
	  if($VMs)
	  {
		'          {
		  "allOf": [
			{
			  "field": "type",
			  "equals": "Microsoft.Compute/virtualMachines"
			},
			{
			  "not": {
				"allOf": [
				  {
                    "field": "Microsoft.Compute/virtualMachines/imageOffer",
					"in": ['+"$vmImageOfferArray1"+']
				  },
				  {
					"field": "Microsoft.Compute/virtualMachines/imagePublisher",
					"in": ['+"$vmImagePublisherArray1"+']
				  },
				  {
					"field": "Microsoft.Compute/virtualMachines/imageSku",
					 "in": ['+"$vmImageSkuArray1"+']
				  },
				  {
					"field": "Microsoft.Compute/virtualMachines/sku.name",
					"in": ['+"$vmSizeArray1"+']
				  }
				]
			  }
			}
		   ]
		},'
	  }

      <#-----------------------------------------------------------------------------------------------------------------------------------------#>
	  if($vmScaleSets)
		{
		'          {
		  "allof": [
			{
			  "field": "type",
			  "equals": "Microsoft.Compute/virtualMachineScaleSets"
			},
			{
			  "not": {
				"field": "Microsoft.Compute/virtualMachineScaleSets/Sku.Name",
				"in": ['+"$vmScaleSetSKUNameArray1"+']
				}
			  }
			]
		  },'
		}

     <#-----------------------------------------------------------------------------------------------------------------------------------------#>
	  if($containerRegistries)
		{
		'          {
		  "allof": [
			{
			  "field": "type",
			  "equals": "Microsoft.ContainerRegistry/registries"
			},
			{
            "field": "Microsoft.ContainerRegistry/registries/sku.name",
            "notIn": ['+"$containerRegistrySKUArray1"+']
            }
			]
		  },'
		}
      
      <#-----------------------------------------------------------------------------------------------------------------------------------------#>
	  if($eventHubs)
		{
		'          {
		  "allof": [
			{
			  "field": "type",
			  "equals": "Microsoft.EventHub/namespaces"
			},
			{
            "field": "Microsoft.EventHub/namespaces/sku.name",
            "notIn": ['+"$eventHubSKUArray1"+']
            }
			]
		  },'
		}

      <#-----------------------------------------------------------------------------------------------------------------------------------------#>
	  if($keyVaults)
		{
		'          {
		  "allof": [
			{
			  "field": "type",
			  "equals": "Microsoft.KeyVault/vaults"
			},
			{
            "field": "Microsoft.KeyVault/vaults/sku.name",
            "notIn": ['+"$keyVaultSKUArray1"+']
            }
			]
		  },'
		}
	
	<#-----------------------------------------------------------------------------------------------------------------------------------------#>
	  if($sqlDatabases) 
		{
		'         {
		  "allof":[
			{
			  "field": "type",
			  "equals": "Microsoft.SQL/servers/databases"
			},
			{
			  "not":{
					"field": "Microsoft.Sql/servers/databases/requestedServiceObjectiveName",
					"in": ['+"$sqlDBServiceObjectiveNameArray1"+']
			  }
			}
		  ]
		},'    
	  }

    <#-----------------------------------------------------------------------------------------------------------------------------------------#>
	  if($storageAccounts)
		{
		'            {
			"allOf": [
			  {
				"source": "action",
				"equals": "Microsoft.Storage/storageAccounts/write"
			  },
			  {
				"field": "type",
				"equals": "Microsoft.Storage/storageAccounts"
			  },
			  {
				"not": 
				  {
					"field": "Microsoft.Storage/storageAccounts/sku.name",
					"in": ['+"$storageSKUArray1"+']
				  }
			   }
			]
		  },'
		}

    <#-----------------------------------------------------------------------------------------------------------------------------------------#>
	  if($appGateways)
		{
		'          {
		  "allof": [
			{
			  "field": "type",
			  "equals": "Microsoft.Network/applicationGateways"
			},
			{
			  "not": {
				"field": "Microsoft.Network/applicationGateways/Sku.Tier",
				"in": ['+"$appGatewaySKUTierArray1"+']
				}
			  }
			]
		  },'
		}

    <#-----------------------------------------------------------------------------------------------------------------------------------------#>
	  if($expressRoutes)
		{
		'          {
		  "allof": [
			{
			  "field": "type",
			  "equals": "Microsoft.Network/expressRouteCircuits"
			},
			{
			  "not": {
				"field": "Microsoft.Network/expressRouteCircuits/Sku.Tier",
				"in": ['+"$expressRoutesSKUTierArray1"+']
				}
			  }
			]
		  },'
		}

     <#-----------------------------------------------------------------------------------------------------------------------------------------#>
	  if($lbs)
		{
		'          {
		  "allof": [
			{
			  "field": "type",
			  "equals": "Microsoft.Network/loadBalancers"
			},
			{
			  "not": {
				"field": "Microsoft.Network/loadBalancers/Sku.Name",
				"in": ['+"$lbSKUNameArray1"+']
				}
			  }
			]
		  },'
		}

    <#-----------------------------------------------------------------------------------------------------------------------------------------#>
	  if($AppServicePlan)
		{
		'          {
		  "allof": [
			{
			  "field": "type",
			  "equals": "Microsoft.Web/serverfarms"
			},
			{
			  "not": {
				"field": "Microsoft.Web/serverfarms/sku.name",
				"in": ['+"$appServicePlanSKUNameArray1"+']
				}
			  }
			]
		  }'
		}

	<#-----------------------------------------------------------------------------------------------------------------------------------------#>
	   '
	  ]
	},
	"then": {
	  "effect": "deny"
	}
}'
	}
	} policy -Passthru | Out-File -filepath C:\Rbac-Policy\Policy\$RGName.json -append
	function Rbac {
	Param(
	[switch]$Passthru
	)
	if($Passthru){
	'
	{
	  "Name": "'+"$rbacName"+'",
	  "Id": null,
	  "IsCustom": true,
	  "Description": "Spektra Training Custom Role.",
	  "Actions": [
		 ' 
		  $resourceTypesForRbac1
		 '
		],
	  "NotActions": [
		 ]
	   }'
	 }
	} 
	Rbac -Passthru | Out-File -filepath C:\Rbac-Policy\Rbac\$RGName.json -append
    (get-content C:\Rbac-Policy\Rbac\$RGName.json) | convertfrom-json | convertto-json -depth 100 | set-content C:\Rbac-Policy\Rbac\$RGName.json
	}
	} RGsOneByOne
	explorer C:\Rbac-Policy\
