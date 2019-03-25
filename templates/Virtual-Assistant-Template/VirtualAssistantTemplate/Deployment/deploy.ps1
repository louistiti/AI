Param(
	[Parameter(Mandatory=$true)][string] $name,
    [Parameter(Mandatory=$true)][string] $location,
    [string] $MicrosoftAppId,
    [string] $MicrosoftAppPassword,
    [string] $resourceGroup = $name,
    [string] $parameters
)

# Get timestamp
$timestamp = Get-Date -f MMddyyyyHHmmss

# Create resource group
Write-Host "Creating resource group ..."
az group create --name $name --location $location | Out-Null


# Deploy Azure services (deploys LUIS, QnA Maker, Content Moderator, CosmosDB)
Write-Host "Deploying Azure services ..."
if($parameters) {
    az group deployment create `
        --name $timestamp `
        --resource-group $resourceGroup `
        --template-file "$(Join-Path $PSScriptRoot 'Resources' 'template.json')" `
        --parameters "@$($parameters)" `
        --parameters microsoftAppId=$MicrosoftAppId microsoftAppPassword=$MicrosoftAppPassword | Out-Null
}
else {
    az group deployment create `
        --name $timestamp `
        --resource-group $resourceGroup `
        --template-file "$(Join-Path $PSScriptRoot 'Resources' 'template.json')" `
        --parameters microsoftAppId=$MicrosoftAppId microsoftAppPassword=$MicrosoftAppPassword | Out-Null
}

# Get deployment outputs
$outputs = az group deployment show -g $resourceGroup -n $timestamp --query properties.outputs | ConvertFrom-Json

# Update appsettings.json
Write-Host "Updating appsettings.json ..."
$settingsPath = Join-Path $PSScriptRoot appsettings.json
$settings = Get-Content $settingsPath | ConvertFrom-Json
$settings | Add-Member -Type NoteProperty -Force -Name 'MicrosoftAppId' -Value $MicrosoftAppId
$settings | Add-Member -Type NoteProperty -Force -Name 'MicrosoftAppPassword' -Value $MicrosoftAppPassword
$settings | Add-Member -Type NoteProperty -Force -Name 'AppInsights' -Value $outputs.appInsights.value
$settings | Add-Member -Type NoteProperty -Force -Name 'BlobStorage' -Value $outputs.storage.value
$settings | Add-Member -Type NoteProperty -Force -Name 'CosmosDb' -Value $outputs.cosmosDb.value
$settings | Add-Member -Type NoteProperty -Force -Name 'ContentModerator' -Value $outputs.contentModerator.value
$settings | ConvertTo-Json -depth 100 | Out-File $settingsPath

# Deploy cognitive models
Invoke-Expression ".\scripts\deploy_cognitive_models.ps1 -name $($name) -location $($location) -luisAuthoringKey  -qnaSubscriptionKey $($outputs.qnaMaker.value.key)"
