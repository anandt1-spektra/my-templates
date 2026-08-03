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

    # --- NEW: Service Principal creds, needed to assign the policy with elevated rights ---
    # NOTE: these are not yet passed in by the current ARM template's userData string.
    # Add -AppId / -AppSecret / -azuserobjectid to the ARM template's arg-building
    # variables (like arg1-arg5) or this block will just warn and skip.
    [string]
    $AppId,

    [string]
    $AppSecret,

    [string]
    $azuserobjectid,

    [string]
    $PolicyJsonUrl = "https://testtemplates123.blob.core.windows.net/gps-frontier/policy-allow-approved-ai-models.json"
)

Start-Transcript -Path C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt -Append
[Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls" 


Function CreateCredFile($AzureUserName, $AzurePassword, $AzureTenantID, $AzureSubscriptionID, $DeploymentID)
{
    # Create the folder BEFORE downloading into it (this was missing before)
    New-Item -ItemType directory -Path C:\LabFiles -force

    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/AzureCreds.txt","C:\LabFiles\AzureCreds.txt")
    $WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/AzureCreds.ps1","C:\LabFiles\AzureCreds.ps1")

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

# =============================================================================
# NEW: Approved AI Models Policy Assignment
#
# Mirrors the pattern used in the AI-Ops lab's psscript.ps1, adapted for the
# new per-model policy (4 approved models, each with its own SKU/capacity
# ceiling instead of one flat rule).
#
# Requires: -AppId / -AppSecret / -azuserobjectid to be passed in (add these
# to the ARM template's arg string). If they aren't supplied, this step is
# skipped with a warning rather than failing the whole deployment.
# =============================================================================

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

# =============================================================================
# Existing lab content setup (unchanged from original)
# =============================================================================

cd C:\LabFiles
mkdir "lab file"

git clone https://github.com/CloudLabsAI-Azure/Accelerate-Agentic-AI-for-Frontier

$destination = "C:\LabFiles\lab file"
$repoFolder = "Accelerate-Agentic-AI-for-Frontier"

New-Item -Path $destination -ItemType Directory -Force | Out-Null
Copy-Item -Path ".\Accelerate-Agentic-AI-for-Frontier\Spectra-cloudslice\Labfiles\*" -Destination $destination -Recurse -Force

if (Test-Path $repoFolder) {
  attrib -r "$repoFolder\*" /s /d 2>$null
  Remove-Item -LiteralPath $repoFolder -Recurse -Force -ErrorAction SilentlyContinue
  if (Test-Path $repoFolder) {
    cmd /c "rmdir /s /q \"$repoFolder\"" | Out-Null
  }
}

choco install azure-cli --version=2.51.0 -y -force

pip install python-dotenv
pip install python-dotenv semantic-kernel
pip install streamlit
pip install fastapi uvicorn
pip install azure-search-documents
code --install-extension GitHub.copilot
code --install-extension ms-python.python

pip install --upgrade pip

pip install azure-ai-projects
pip install azure-identity

#pip install -r https://experienceazure.blob.core.windows.net/templates/azure-aI-agents/scripts/requirements.txt

#install the ml extension:
az extension add -n ml
az ml -h
az extension update -n ml

Start-Process -FilePath "C:\Program Files (x86)\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe" `
    -ArgumentList "/silent /install appguid={56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}&appname=Microsoft%20Edge&needsadmin=True" `
    -Wait

Stop-Transcript
Disable-ScheduledTask -TaskName "runuserdata"
Stop-ScheduledTask -TaskName "runuserdata"
