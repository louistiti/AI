Param(
	[Parameter(Mandatory=$true)][string] $name,
    [Parameter(Mandatory=$true)][string] $location,
    [string] $luisAuthoringKey,
    [string] $resourceGroup = $name,
    [string] $parametersFile
)

# Get timestamp
$timestamp = Get-Date -f MMddyyyyHHmmss

# Create resource group
Write-Host "Creating resource group ..."
$group = az group create --name $name --location $location

# Launch login page
Start-Process -Path "https://microsoft.com/devicelogin"

# Create bot registration
$bot = az bot create `
    --kind registration `
    --name $name `
    --resource-group $resourceGroup `
    --endpoint "https://www.bing.com"

# Deploy Azure services (deploys LUIS, QnA Maker, Content Moderator, CosmosDB)
Write-Host "Deploying Azure services ..."
if($parametersFile) {
    az group deployment create `
        --name $timestamp `
        --resource-group $resourceGroup `
        --template-file "$(Join-Path $PSScriptRoot 'Resources' 'template.json')" `
        --parameters "@$($parametersFile)" `
        --parameters microsoftAppId=$bot.properties.msaAppId microsoftAppPassword=$bot.properties.password | Out-Null
}
else {
    az group deployment create `
        --name $timestamp `
        --resource-group $resourceGroup `
        --template-file "$(Join-Path $PSScriptRoot 'Resources' 'template.json')" `
        --parameters microsoftAppId=$bot.properties.msaAppId microsoftAppPassword=$bot.properties.msaAppPassword | Out-Null
}

# Get deployment outputs
$outputs = az group deployment show -g $resourceGroup -n $timestamp --query properties.outputs | ConvertFrom-Json

# Update bot settings
az bot update `
    --name $name `
    --resource-group $resourceGroup `
    --set properties.developerAppInsightKey=$outputs.appInsights.instrumentationKey properties.developerAppInsightsApplicationId=$outputs.appInsights.appId properties.endpoint=$outputs.bot.endpoint | Out-Null

# Update appsettings.json
Write-Host "Updating appsettings.json ..."
$settingsPath = Join-Path $PSScriptRoot appsettings.json
$settings = Get-Content $settingsPath | ConvertFrom-Json
$settings | Add-Member -Type NoteProperty -Force -Name 'MicrosoftAppId' -Value $bot.properties.msaAppId
$settings | Add-Member -Type NoteProperty -Force -Name 'MicrosoftAppPassword' -Value $bot.properties.msaAppPassword
$settings | Add-Member -Type NoteProperty -Force -Name 'AppInsights' -Value $outputs.appInsights.value
$settings | Add-Member -Type NoteProperty -Force -Name 'BlobStorage' -Value $outputs.storage.value
$settings | Add-Member -Type NoteProperty -Force -Name 'CosmosDb' -Value $outputs.cosmosDb.value
$settings | Add-Member -Type NoteProperty -Force -Name 'ContentModerator' -Value $outputs.contentModerator.value
$settings | ConvertTo-Json -depth 100 | Out-File $settingsPath

# Deploy cognitive models
Invoke-Expression ".\scripts\deploy_cognitive_models.ps1 -name $($name) -location $($location) -luisAuthoringKey $luisAuthoringKey -qnaSubscriptionKey $($outputs.qnaMaker.value.key)"