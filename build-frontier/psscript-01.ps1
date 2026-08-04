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
    $InstallCloudLabsShadow,

    [string]
    $DeploymentID,

    [string]
    $vmAdminUsername,

    [string]
    $vmAdminPassword,

    [string]
    $trainerUserName,

    [string]
    $trainerUserPassword,
    
    [string]
    $AppId,

    [string]
    $AppSecret,

    [string]
    $azuserobjectid,

    [string]
    $PolicyJsonUrl = "https://raw.githubusercontent.com/anandt1-spektra/my-templates/refs/heads/main/build-frontier/policy-allow-approved-ai-models.json"
)

Start-Transcript -Path C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt -Append
[Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

Function CreateCredFile($AzureUserName, $AzurePassword, $AzureTenantID, $AzureSubscriptionID, $DeploymentID)
{
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/AzureCreds.txt","C:\LabFiles\AzureCreds.txt")
    $WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/AzureCreds.ps1","C:\LabFiles\AzureCreds.ps1")

    New-Item -ItemType directory -Path C:\LabFiles -force

    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzureUserNameValue", "$AzureUserName"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzurePasswordValue", "$AzurePassword"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzureTenantIDValue", "$AzureTenantID"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzureSubscriptionIDValue", "$AzureSubscriptionID"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "DeploymentIDValue", "$DeploymentID"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"

    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzureUserNameValue", "$AzureUserName"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzurePasswordValue", "$AzurePassword"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzureTenantIDValue", "$AzureTenantID"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzureSubscriptionIDValue", "$AzureSubscriptionID"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "DeploymentIDValue", "$DeploymentID"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"

    Copy-Item "C:\LabFiles\AzureCreds.txt" -Destination "C:\Users\Public\Desktop"
}

CreateCredFile $AzureUserName $AzurePassword $AzureTenantID $AzureSubscriptionID $DeploymentID

Function updateVMShadowFile
{
#Replace vmAdminUsernameValue with VM Admin UserName in script content
$drivepath="C:\Users\Public\Documents"
(Get-Content -Path "$drivepath\Shadow.ps1") | ForEach-Object {$_ -Replace "vmAdminUsernameValue", "$vmAdminUsername"} | Set-Content -Path "$drivepath\Shadow.ps1"
#Update random password
net user $trainerUserName $trainerUserPassword
}
updateVMShadowFile

Function RunModernVmValidator
{
cmd.exe --% /c sc create "Spektra CloudLabs VM Agent" BinPath=C:\CloudLabs\Validator\VMAgent\Spektra.CloudLabs.VMAgent.exe start= auto
cmd.exe --% /c sc start "Spektra CloudLabs VM Agent"
}
RunModernVmValidator

sleep 5

Function CloneLabFiles
{
    $RepoUrl     = "https://github.com/CloudLabsAI-Azure/MsIQ-cplt-agntsfrntr.git"
    $Branch      = "post-build-SPLabs"
    $SourcePath  = "Lab Files"
    $Destination = "C:\Lab Files"
    $TempDir     = Join-Path $env:TEMP "MsIQ-clone-$(Get-Random)"

    # Ensure git is available; install via choco if missing
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        choco install git -y --no-progress
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }

    Write-Host "Cloning '$SourcePath' from $RepoUrl ($Branch)..."

    # Shallow, blobless, sparse clone - downloads only the Lab Files folder
    git clone --depth 1 --filter=blob:none --sparse --branch $Branch $RepoUrl $TempDir
    Push-Location $TempDir
    git sparse-checkout set $SourcePath
    Pop-Location

    if (-not (Test-Path $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    Copy-Item -Path (Join-Path $TempDir $SourcePath | Join-Path -ChildPath "*") -Destination $Destination -Recurse -Force

    Remove-Item $TempDir -Recurse -Force
    Write-Host "Lab Files copied to $Destination"
}
CloneLabFiles

Function Set-ApprovedAIModelsPolicy
{
    param(
        [string]$AppId,
        [string]$AppSecret,
        [string]$AzureTenantID,
        [string]$AzureSubscriptionID,
        [string]$PolicyJsonUrl
    )

    if ([string]::IsNullOrWhiteSpace($AppId) -or [string]::IsNullOrWhiteSpace($AppSecret)) {
        Write-Warning "Set-ApprovedAIModelsPolicy: AppId/AppSecret not supplied - skipping policy assignment. Add these params to the ARM template to enable this step."
        return
    }

    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    # The Az PowerShell module (Connect-AzAccount, Get-AzPolicyDefinition, etc.)
    # is NOT installed anywhere else in this script - only azure-cli is. Install it here.
    Write-Host "Installing Az PowerShell module (required for policy assignment)..." -ForegroundColor Cyan
    choco install az.powershell -y

    # Force-import the Az.Accounts module into the current session.
    # choco installs the module to disk but does NOT load it into the running
    # PowerShell session automatically. Without this, Connect-AzAccount /
    # Select-AzSubscription are unavailable and the context is never established,
    # which produces "Please provide a valid tenant or a valid subscription."
    $azModulePath = "C:\Program Files\WindowsPowerShell\Modules\Az.Accounts"
    if (Test-Path $azModulePath) {
        Import-Module Az.Accounts -Force -ErrorAction Stop
    } else {
        # Fallback: let PowerShell auto-discover from PSModulePath
        Import-Module Az.Accounts -Force -ErrorAction Stop
    }

    # --- Login using the Service Principal ---
    $securePassword = $AppSecret | ConvertTo-SecureString -AsPlainText -Force
    $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AppId, $securePassword
    # Pass -Subscription directly so tenant + subscription context are set in one call.
    # Do NOT pipe to Out-Null — suppressing output also hides login errors.
    Write-Host "Authenticating with Service Principal..." -ForegroundColor Cyan
    Connect-AzAccount -ServicePrincipal -Credential $cred -Tenant $AzureTenantID -Subscription $AzureSubscriptionID | Out-Null
    Set-AzContext -TenantId $AzureTenantID -SubscriptionId $AzureSubscriptionID | Out-Null

    $PolicyDefinitionName = "Allow-ApprovedAIModels"
    $PolicyAssignmentName = "Allow-ApprovedAIModels"
    $PolicyFile = Join-Path $env:TEMP "Allow-ApprovedAIModels.json"

    Write-Host "Downloading policy definition..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $PolicyJsonUrl -OutFile $PolicyFile

    $Policy = Get-Content $PolicyFile -Raw | ConvertFrom-Json

    # Create or Update Policy Definition
    # Az.Resources v10+ throws a terminating error (not a non-terminating one) when
    # the definition is not found, so -ErrorAction SilentlyContinue is not enough.
    # Wrap in try/catch so a missing definition is treated as $null, not a fatal error.
    $ExistingPolicy = $null
    try {
        $ExistingPolicy = Get-AzPolicyDefinition -Name $PolicyDefinitionName -ErrorAction Stop
    } catch {
        $ExistingPolicy = $null
    }

    if ($null -eq $ExistingPolicy)
    {
        Write-Host "Creating Policy Definition..." -ForegroundColor Cyan
        New-AzPolicyDefinition `
            -Name $PolicyDefinitionName `
            -DisplayName $Policy.properties.displayName `
            -Description $Policy.properties.description `
            -Policy $PolicyFile `
            -Mode $Policy.properties.mode | Out-Null
    }
    else
    {
        Write-Host "Updating existing Policy Definition..." -ForegroundColor Cyan
        Set-AzPolicyDefinition `
            -Name $PolicyDefinitionName `
            -Policy $PolicyFile | Out-Null
    }

    # Create Policy Assignment (subscription scope)
    $scope = "/subscriptions/$AzureSubscriptionID"

    # Same issue applies to Get-AzPolicyAssignment — wrap in try/catch.
    $ExistingAssignment = $null
    try {
        $ExistingAssignment = Get-AzPolicyAssignment `
            -Name $PolicyAssignmentName `
            -Scope $scope `
            -ErrorAction Stop
    } catch {
        $ExistingAssignment = $null
    }

    if ($null -eq $ExistingAssignment)
    {
        Write-Host "Assigning policy..." -ForegroundColor Cyan
        $PolicyDef = Get-AzPolicyDefinition -Name $PolicyDefinitionName

        New-AzPolicyAssignment `
            -Name $PolicyAssignmentName `
            -DisplayName $Policy.properties.displayName `
            -PolicyDefinition $PolicyDef `
            -Scope $scope | Out-Null
    }
    else
    {
        Write-Host "Policy assignment already exists." -ForegroundColor Yellow
    }

    Write-Host "Approved AI Models policy is in place (gpt-5.4, gpt-5.4-mini, gpt-5.2, text-embedding-3-large)." -ForegroundColor Green
}

Set-ApprovedAIModelsPolicy -AppId $AppId -AppSecret $AppSecret -AzureTenantID $AzureTenantID -AzureSubscriptionID $AzureSubscriptionID -PolicyJsonUrl $PolicyJsonUrl

sleep 10 

# Upgrate
choco --version

choco upgrade vscode -y

sleep 10
code --install-extension TeamsDevApp.ms-teams-vscode-extension

sleep 5
# choco install visualstudio2022community -y

sleep 5

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\Visual Studio 2022.lnk")
$Shortcut.TargetPath = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe"
$Shortcut.Save()

Stop-Transcript
Disable-ScheduledTask -TaskName "runuserdata"
Stop-ScheduledTask -TaskName "runuserdata"
