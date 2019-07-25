<#
.Synopsis
    Script to deploy services to Kubernetes either using local computer or Azure DevOps.
.DESCRIPTION
    Local usage:
        deploy-service.ps1 -devBuilder -service <serviceName>
    Azure DevOps usage:
        deploy-service.ps1 -azureDevOps -service <serviceName> -environmentShort <environmentShort>
    To create variables for common deploy:
        deploy-service.ps1 -commonDeploy -environmentShort <environmentShort>
.NOTES
    Name: deploy-service.ps1
    Author: Simon Gottschlag
    Date Created: 2019-03-29
    Version History:
        2019-03-29 - Simon Gottschlag
            Initial Creation


    Xenit AB
#>

[cmdletbinding(DefaultParameterSetName = 'devBuilder')]
Param(
    [Parameter(Mandatory = $true, ParameterSetName = 'devBuilder')]
    [Parameter(Mandatory = $true, ParameterSetName = 'azureDevOps')]
    [Parameter(Mandatory = $false, ParameterSetName = 'commonDeploy')]
    [string]$service,
    [Parameter(Mandatory = $false, ParameterSetName = 'devBuilder')]
    [Parameter(Mandatory = $true, ParameterSetName = 'azureDevOps')]
    [Parameter(Mandatory = $true, ParameterSetName = 'commonDeploy')]
    [string]$environmentShort = "dev",
    [string]$variableFile = "$($PSScriptRoot)/variables.json",
    [Parameter(Mandatory = $true, ParameterSetName = 'devBuilder')]
    [switch]$devBuilder,
    [Parameter(Mandatory = $true, ParameterSetName = 'azureDevOps')]
    [switch]$azureDevOps,
    [Parameter(Mandatory = $true, ParameterSetName = 'commonDeploy')]
    [switch]$commonDeploy,
    [switch]$followLogs
)

Begin {
    $ErrorActionPreference = "Stop"

    # Convert variables.json to powershell object
    $allVariables = Get-Content $variableFile | ConvertFrom-Json

    # Define regex to use to extract
    $regex = [regex] "#{([a-zA-Z0-9]+)}#"
    $regexStart = "#{"
    $regexEnd = "}#"

    # Set build id
    if ($ENV:BUILD_BUILDID -ne $null) {
        $buildId = $ENV:BUILD_BUILDID
        $devBuildId = $null
    }
    else {
        $buildId = New-Guid
        $devBuildId = $buildId
    }

    # Create powershell objects for variables to manipulate
    $commonVariables = $allVariables.common
    $commonVariablesAll = $commonVariables.variables.all
    $commonVariablesEnv = $commonVariables.variables.$environmentShort
    $serviceVariables = $allVariables.$service
    $serviceVariablesAll = $serviceVariables.variables.all
    $serviceVariablesEnv = $serviceVariables.variables.$environmentShort
    $serviceVariablesObject = New-Object -TypeName psobject

    # Function to retrun error code correctly from binaries
    function Invoke-Call {
        param (
            [scriptblock]$ScriptBlock,
            [string]$ErrorAction = $ErrorActionPreference
        )
        & @ScriptBlock
        if (($lastexitcode -ne 0) -and $ErrorAction -eq "Stop") {
            exit $lastexitcode
        }
    }
    function Initialize-ServiceVariables {
        param (
            [PSObject]$serviceObject,
            [PSObject]$variableObject
        )
        foreach ($pair in $variableObject.PSObject.Properties) {
            try {
                $serviceObject | Add-Member -MemberType NoteProperty -Name $($pair.name) -Value $($pair.value)
            }
            catch {
                $serviceObject.$($pair.name) = $($pair.value)
            }
        }
        return $serviceObject
    }

    function Set-ServiceVariables {
        param (
            [PSObject]$serviceObject
        )
        $continueLoop = $true
        while ($continueLoop) {
            $continueLoop = $false
            foreach ($pair in $serviceObject.PSObject.Properties) {
                $key = $pair.name
                $value = $pair.value
                if ($value -match $regexStart -and $value -match $regexEnd) {
                    $v1 = $value | Select-String -Pattern $regex -AllMatches | ForEach-Object { $_.Matches }
                    foreach ($v2 in $v1) {
                        $replaceKeyValue = $v2.Groups[0].Value
                        $replaceKeyName = $v2.Groups[1].Value
                        if ($null -ne $serviceVariablesObject.$replaceKeyName) {
                            $serviceVariablesObject.$key = $serviceVariablesObject.$key -replace $replaceKeyValue, $serviceVariablesObject.$replaceKeyName
                            $continueLoop = $true
                        }
                    }
                }
            }
        }

        # Create session variables based on the service variables object
        foreach ($pair in $serviceObject.PSObject.Properties) {
            if ($commonDeploy) {
                Write-Output "##vso[task.setvariable variable=$($pair.name)]$($pair.value)"
            }
            Set-Variable -Name $pair.name -Value $pair.value -Scope Script
        }
    }
}
Process {
    $serviceVariablesObject = Initialize-ServiceVariables -serviceObject $serviceVariablesObject -variableObject $commonVariablesAll
    $serviceVariablesObject = Initialize-ServiceVariables -serviceObject $serviceVariablesObject -variableObject $commonVariablesEnv
    
    if (!$commonDeploy) {
        $serviceVariablesObject = Initialize-ServiceVariables -serviceObject $serviceVariablesObject -variableObject $serviceVariablesAll
        $serviceVariablesObject = Initialize-ServiceVariables -serviceObject $serviceVariablesObject -variableObject $serviceVariablesEnv
    }
    
    Set-ServiceVariables -serviceObject $serviceVariablesObject

    switch ($PSCmdlet.ParameterSetName) {
        'devBuilder' {
            if ($PSVersionTable.PSEdition -ne "Core") {
                Write-Error "This script requires Powershell Core or else we can't use `$IsOS like `$IsWindows"
            }

            if ($IsWindows) {
                $tmpDirectory = "$($ENV:TMP)"
                $kubeConfig = "$($ENV:USERPROFILE)\.kube\config"
            }
            else {
                $tmpDirectory = "/tmp"
                $kubeConfig = "$($ENV:HOME)/.kube/config"
            }
            
            $image = "$($applicationName)-devbuilder:latest"
            $remoteImage = "$($dockerRegistry)/$($projectName)/$($image)"
            $hpaMaxReplicas = 1
    
            try {
                # Defined binaries
                $dockerBin = $(Get-Command docker -ErrorAction Stop)
                $helmBin = $(Get-Command helm -ErrorAction Stop)
                $kubectlBin = $(Get-Command kubectl -ErrorAction Stop)

                # Login to Azure Container Registry
                $azBin = $(Get-Command az -ErrorAction Stop)
                Invoke-Call ([ScriptBlock]::Create("$azBin acr login -n $($acrName)"))
            }
            catch {
                $ErrorMessage = $_.Exception.Message
                $FailedItem = $_.Exception.ItemName
                Write-Output "Executable missing, see below error."
                Write-Error "Message: $ErrorMessage`r`nItem: $FailedItem"
                break
            }
        }
        'azureDevOps' {
            #$tmpDirectory = $($ENV:SYSTEM_DEFAULTWORKINGDIRECTORY)
            $tmpDirectory = "/tmp"
            $ENV:PATH = "$($ENV:PATH):$($tmpDirectory)"
            $chmodBin = $(Get-Command chmod -ErrorAction Stop)
            $bashBin = $(Get-Command bash -ErrorAction Stop)

            # Download and install helm
            $retrycount = 0
            While (-not (test-path -LiteralPath "$($tmpDirectory)/get_helm.sh" -PathType Leaf)) {
                Try {
                    Invoke-WebRequest -Uri https://raw.githubusercontent.com/helm/helm/master/scripts/get -OutFile "$($tmpDirectory)/get_helm.sh" -ErrorAction Stop
                }
                catch {
                    $waittime = get-random -Minimum 20 -Maximum 30
                    Start-Sleep -Seconds $waittime
                    $retrycount++
                    If ($retrycount -gt 5) {
                        Throw "failed to download helm"
                    }
                }
            }
            Invoke-Call ([ScriptBlock]::Create("$chmodBin 700 $($tmpDirectory)/get_helm.sh"))
            $ENV:HELM_INSTALL_DIR = "$($tmpDirectory)"
            Invoke-Call ([ScriptBlock]::Create("$bashBin $($tmpDirectory)/get_helm.sh --no-sudo"))

            # Download and install kubectl
            $retrycount = 0
            While (-not (test-path -LiteralPath "$($tmpDirectory)/kubectl" -PathType Leaf)) {
                Try {
                    $latestKubectlVersion = (Invoke-WebRequest https://storage.googleapis.com/kubernetes-release/release/stable.txt -ErrorAction Stop).Content.Trim()
                    Invoke-WebRequest -Uri https://storage.googleapis.com/kubernetes-release/release/$($latestKubectlVersion)/bin/linux/amd64/kubectl -OutFile "$($tmpDirectory)/kubectl" -ErrorAction Stop
                }
                catch {
                    $waittime = get-random -Minimum 20 -Maximum 30
                    Start-Sleep -Seconds $waittime
                    $retrycount++
                    If ($retrycount -gt 5) {
                        Throw "failed to download kubectl"
                    }
                }
            }
            Invoke-Call ([ScriptBlock]::Create("$chmodBin +x $($tmpDirectory)/kubectl"))

            # Defined binaries
            $helmBin = "$($tmpDirectory)/helm"
            $kubectlBin = "$($tmpDirectory)/kubectl"

            # Login to Azure Kubernetes Service
            $azBin = $(Get-Command az -ErrorAction Stop)
            $kubeConfig = "$($tmpDirectory)/kubeconfig"
            Invoke-Call ([ScriptBlock]::Create("$azBin aks get-credentials --resource-group $($resourceGroupName) --name $($aksName) --file=$($kubeConfig) --overwrite-existing"))
        }
        'commonDeploy' {
            Write-Output "Common deploy - exiting."
            exit 0
        }
        default {
            Write-Error "Neither devBuilder or azureDevOps defined."
            exit 1
        }
    }

    $applicationSrcPath = "$($PSScriptRoot)/../src/$($serviceType)-$($applicationName)"

    try {
        # If running as devbuilder, run docker build/tag/push
        if ($devBuilder) {
            if (Test-Path -PathType Leaf -Path "$($applicationSrcPath)/Dockerfile") {
                $dockerFile = "$($applicationSrcPath)/Dockerfile"
            }
            else {
                $dockerFile = "$($PSScriptRoot)/Dockerfile"
            }

            Invoke-Call ([ScriptBlock]::Create("$dockerBin build --rm --build-arg SERVICE=$($applicationName) --build-arg SERVICE_TYPE=$($serviceType) --build-arg PACKAGE_SCOPE=$($projectName) -f $($dockerFile) -t $image `"$($PSScriptRoot)/..`""))
            Invoke-Call ([ScriptBlock]::Create("$dockerBin tag $image $remoteImage"))
            Invoke-Call ([ScriptBlock]::Create("$dockerBin push $remoteImage"))
        }

        # Grab the current version running
        $currentImage = Invoke-Call ([ScriptBlock]::Create("$kubectlBin --kubeconfig=$($kubeConfig) --namespace=$($namespace) get deployment -l app=$($applicationName) -o jsonpath='{ .items[*].spec.template.spec.containers[*].image }'"))

        # Generate Kubernetes manifest from the helm chart
        & $helmBin template "$($PSScriptRoot)/../.kubernetes/service" `
            --set global.environmentShort=$environmentShort `
            --set application.remoteImage="$($remoteImage)" `
            --set application.devBuildId="$($devBuildId)" `
            --set application.name=$applicationName `
            --set application.buildId=$buildId `
            --set application.subDomain=$subDomain `
            --set ingress.enabled=$ingressEnabled `
            --set application.allowedServices="$($allowedServices)" `
            --set application.path="$($applicationPath)" `
            --set mongodb.enabled="$($mongodbEnabled)" `
            --set redis.enabled="$($redisEnabled)" `
            --set application.horizontalPodAutoscaler.maxReplicas=$($hpaMaxReplicas) `
            --set application.resources.limits.memory=$resourcesMemLimit `
            --set application.resources.limits.cpu=$resourcesCpuLimit `
            --set application.resources.request.memory=$resourcesMemRequest `
            --set application.resources.request.cpu=$resourcesCpuRequest | Out-File -FilePath "$($tmpDirectory)/k8smanifest.yaml"
        
        # Break if exit code from helm/kubectl
        if (!$?) {
            break
        }

        Get-Content "$($tmpDirectory)/k8smanifest.yaml"
        Invoke-Call ([ScriptBlock]::Create("$kubectlBin --kubeconfig=$($kubeConfig) --namespace=$($namespace) apply -f $($tmpDirectory)/k8smanifest.yaml"))

        if ($currentImage -eq $remoteImage -and $devBuilder) {
            Write-Output "Deleting pods since current image is same as remote image."
            Invoke-Call ([ScriptBlock]::Create("$kubectlBin --kubeconfig=$($kubeConfig) --namespace=$($namespace) delete pod -l app=$($applicationName)"))
        }
        if ($azureDevOps) {
            Write-Output "Azure DevOps: Pausing script for 15 seconds."
            Start-Sleep 15
        }

        $podReady = $false
        
        if ($azureDevOps) {
            $sleepTime = 10
            $maxCount = 20
        } 
        else {
            $sleepTime = 5
            $maxCount = 10
        }

        $counter = 0
        while (!$podReady) {
            $counter ++
            if ($counter -ge $maxCount) {
                "Exiting podReady loop."
                break
            }
            else {
                "podReady loop: $($counter)/$($maxCount)"
            }

            try {
                $podOutput = Invoke-Call ([ScriptBlock]::Create("$kubectlBin --kubeconfig=$($kubeConfig) --namespace=$($namespace) get pod -l app=$($applicationName),buildId=$($buildId) -o json"))
                $containerStatusArray = (($podOutput | ConvertFrom-Json -ErrorAction Stop).items.status.ContainerStatuses.state | ForEach-Object { $_ | Get-Member -MemberType Properties | Select-Object Name })
            }
            catch {
                Write-Output "Pod not ready..."
                Start-Sleep $sleepTime
                continue
            }
            
            $statusReady = $true
            if ($containerStatusArray.count -eq 0) {
                $statusReady = $false
            }

            foreach ($containerStatus in $containerStatusArray.Name) {
                if ($containerStatus -ne "running") {
                    $statusReady = $false
                }
            }

            if (!$statusReady) {
                Write-Output "Pod not ready..."
                Start-Sleep $sleepTime
                continue
            }
            
            $podReady = $true
        }

        if ($podReady) {
            if ($followLogs) {
                try {
                    $podName = Invoke-Call ([ScriptBlock]::Create("$kubectlBin --kubeconfig=$($kubeConfig) -n $($namespace) get pod -l app=$($applicationName),buildId=$($buildId) -o jsonpath='{.items[0].metadata.name}'"))
                }
                catch {
                    Write-Output "Information: Errors from POD logs suppressed."
                }
                Write-Output "POD is ready! Following logs:"
                Invoke-Call ([ScriptBlock]::Create("$kubectlBin --kubeconfig=$($kubeConfig) -n $($namespace) logs --follow $($podName) $($applicationName)"))
            }
            else {
                Write-Output "POD is ready! See below for the current logs:"
                Invoke-Call ([ScriptBlock]::Create("$kubectlBin --kubeconfig=$($kubeConfig) --namespace=$($namespace) logs -l app=$($applicationName),buildId=$($buildId) -c $($applicationName)"))
                Write-Output ""
                Write-Output "------------------------------------------"
                Write-Output ""
                Write-Output "Run the following command to tail the log:"
                try {
                    $podName = Invoke-Call ([ScriptBlock]::Create("$kubectlBin --kubeconfig=$($kubeConfig) -n $($namespace) get pod -l app=$($applicationName),buildId=$($buildId) -o jsonpath='{.items[0].metadata.name}'"))
                }
                catch {
                    Write-Output "Information: Errors from POD logs suppressed."
                }
                Write-Output "kubectl -n $($namespace) logs --follow $($podName) $($applicationName)"
            }
        }
        else {
            Write-Output "POD is NOT ready! See below for current logs:"
            Invoke-Call ([ScriptBlock]::Create("$kubectlBin --kubeconfig=$($kubeConfig) --namespace=$($namespace) logs -l app=$($applicationName),buildId=$($buildId) -c $($applicationName)"))
            Write-Error "Please redeploy the latest version from CI/CD to get it working again."
        }

    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $FailedItem = $_.Exception.ItemName
        Write-Error "Message: $ErrorMessage`r`nItem: $FailedItem"
        exit 1
    }
}
End {
    
}