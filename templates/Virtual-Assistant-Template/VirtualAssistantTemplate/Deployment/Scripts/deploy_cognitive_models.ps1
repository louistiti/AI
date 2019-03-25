Param(
	[Parameter(Mandatory=$true)][string] $name,
    [Parameter(Mandatory=$true)][string] $location,
    [string] $luisAuthoringKey,
    [string] $qnaSubscriptionKey,
    [string] $languages = "en-us"
)

. $PSScriptRoot\luis_functions.ps1
. $PSScriptRoot\qna_functions.ps1

# Deploy localized resources
Write-Host "Deploying cognitive models ..."
foreach ($language in $languages -split ",")
{
    $langCode = ($language -split "-")[0]

    # Initialize config
    $settings = @{ cognitiveModels = @() }

    # Initialize Dispatch
    Write-Host "Initializing dispatch model ..."
    $dispatchName = "$($name)$($langCode)_Dispatch"
    $dataFolder = Join-Path $PSScriptRoot .. Resources Dispatch $langCode
    $dispatch = dispatch init `
        --name $dispatchName `
        --luisAuthoringKey $luisAuthoringKey `
        --luisAuthoringRegion $location `
        --dataFolder $dataFolder

    # Deploy LUIS apps
    $luisFiles = Get-ChildItem "$(Join-Path $PSScriptRoot .. 'Resources' 'LU' $langCode)" | Where {$_.extension -eq ".lu"}
    foreach ($lu in $luisFiles)
    {
        # Deploy LUIS model
        $luisApp = DeployLUIS -name $name -lu_file $lu -region $location -luisAuthoringKey $luisAuthoringKey -language $language
        
        # Add luis app to dispatch
        Write-Host "Adding $($id) app to dispatch model ..."
        dispatch add `
            --type "luis" `
            --name $luisApp.name `
            --id $luisApp.id  `
            --intentName "l_$($id)" `
            --dataFolder $dataFolder `
            --dispatch "$(Join-Path $dataFolder "$($dispatchName).dispatch")" | Out-Null
        
        # Add to config 
        $settings.cognitivemodels += @{
           
            version = $luisApp.activeVersion
            region = $location
            subscriptionkey = $luisauthoringkey
            authoringkey = $luisauthoringkey
            appid = $luisApp.id
            name = $luisApp.name
            id = $lu.BaseName
            type = "luis"
        }
    }

    # Deploy QnA Maker KBs
    $qnaFiles = Get-ChildItem "$(Join-Path $PSScriptRoot .. 'Resources' 'QnA' $langCode)" -Recurse | Where {$_.extension -eq ".lu"} 
    foreach ($lu in $qnaFiles)
    {
        # Deploy QnA Knowledgebase
        $qnaKb = DeployKB -name $name -lu_file $lu -qnaSubscriptionKey $qnaSubscriptionKey
       
        # Add luis app to dispatch
        Write-Host "Adding $($id) kb to dispatch model ..."        
        dispatch add `
            --type "qna" `
            --name $qnaKb.name `
            --id $qnaKb.id  `
            --key $qnaSubscriptionKey `
            --intentName "q_$($id)" `
            --dataFolder $dataFolder `
            --dispatch "$(Join-Path $dataFolder "$($dispatchName).dispatch")" | Out-Null
        
        # Add to config
        $settings.cognitiveModels += @{
            type = "qna"
            id = $lu.BaseName
            name = $qnaKb.name
            kbId = $qnaKb.kbId
            subscriptionKey = $qnaKb.subscriptionKey
            endpointKey = $qnaKb.endpointKey
            hostname = $qnaKb.hostname
        }
    }


    # Create dispatch model
    Write-Host "Creating dispatch model..."  
    $dispatch = dispatch create `
        --dispatch "$(Join-Path $dataFolder "$($dispatchName).dispatch")" `
        --dataFolder  $dataFolder `
        --culture $language | ConvertFrom-Json
    
    $settings.cognitivemodels += @{
        type = "dispatch"
        name = $dispatch.name
        appid = $dispatch.appId
        authoringkey = $luisauthoringkey
        subscriptionkey = $luisauthoringkey
        region = $location   
    }

    # Write out config to file
    $settings | ConvertTo-Json -depth 100 | Out-File $(Join-Path $PSScriptRoot ".." "cognitivemodels.$($langCode).json" )
}