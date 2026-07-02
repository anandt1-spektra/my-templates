Param (
    [Parameter(Mandatory = $true)][string]$AzureUserName,
    [string]$AzurePassword,
    [string]$AzureTenantID,
    [string]$AzureSubscriptionID,
    [string]$ODLID,
    [string]$DeploymentID,
    [string]$azuserobjectid,
    [string]$InstallCloudLabsShadow,
    [string]$AdminUsername,
    [string]$adminPassword,
    [string]$location,
    [string]$trainerUserName,
    [string]$trainerUserPassword,
    [string]$vmAdminUsername,
    [string]$AppID,
    [string]$AppSecret
)

# Basic parsing of UPN (kept in case you need tenant name later)
$Inputstring = $AzureUserName
$CharArray   = $InputString.Split("@")

Start-Transcript -Path C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt -Append
[Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
Write-Output "TLS setting: $([Net.ServicePointManager]::SecurityProtocol)"

# Expose SP and object id as machine env vars (CloudLabs convention)
[System.Environment]::SetEnvironmentVariable('AppID', $AppID, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('AppSecret', $AppSecret, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('azuserobjectid', $azuserobjectid, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('AzureSubscriptionID', $AzureSubscriptionID, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('AzureTenantID', $AzureTenantID, [System.EnvironmentVariableTarget]::Machine)

# CloudLabs common functions

$path = (Get-Location).Path
$commonscriptpath = "$path\cloudlabs-common\cloudlabs-windows-functions.ps1"
. $commonscriptpath

#InstallManualStatusAgent
CloudlabsManualAgent Install

# Run Imported functions from cloudlabs-windows-functions.ps1
WindowsServerCommon
InstallCloudLabsShadow $ODLID $InstallCloudLabsShadow

Function CreateCredFile($AzureUserName, $AzurePassword, $AzureTenantID, $AzureSubscriptionID, $DeploymentID, $AppID, $AppSecret)
{
    New-Item -ItemType directory -Path C:\LabFiles -force

    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile("https://raw.githubusercontent.com/anandt1-spektra/my-templates/refs/heads/main/sqldatawarehouse/AzureCreds.txt","C:\LabFiles\AzureCreds.txt")
    $WebClient.DownloadFile("https://raw.githubusercontent.com/anandt1-spektra/my-templates/refs/heads/main/sqldatawarehouse/AzureCreds.ps1","C:\LabFiles\AzureCreds.ps1")

    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzureUserNameValue", "$AzureUserName"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzurePasswordValue", "$AzurePassword"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzureTenantIDValue", "$AzureTenantID"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzureSubscriptionIDValue", "$AzureSubscriptionID"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "DeploymentIDValue", "$DeploymentID"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AppIDValue", "$AppID"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AppSecretValue", "$AppSecret"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"

    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzureUserNameValue", "$AzureUserName"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzurePasswordValue", "$AzurePassword"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzureTenantIDValue", "$AzureTenantID"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzureSubscriptionIDValue", "$AzureSubscriptionID"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "DeploymentIDValue", "$DeploymentID"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AppIDValue", "$AppID"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
    (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AppSecretValue", "$AppSecret"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"

    Copy-Item "C:\LabFiles\AzureCreds.txt" -Destination "C:\Users\Public\Desktop"
}

CreateCredFile $AzureUserName $AzurePassword $AzureTenantID $AzureSubscriptionID $DeploymentID $AppID $AppSecret
InstallModernVmValidator


# Enable CloudLabs Embedded Shadow Feature (trainer ↔ VM)
Enable-CloudLabsEmbeddedShadow $vmAdminUsername $trainerUserName $trainerUserPassword

InstallChocolatey

Invoke-WebRequest -Uri "https://raw.githubusercontent.com/SpektraSystems/CloudLabs-Azure/master/azure-synapse-analytics-workshop-400/artifacts/setup/azcopy.exe" -OutFile "C:\LabFiles\azcopy.exe"

# Add-Content -Path "C:\LabFiles\AzureCreds.txt" -Value "ODLID= $ODLID" -PassThru

#Download lab files
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://github.com/CloudLabsAI-Azure/azure-synapse-analytics-day/archive/master.zip","C:\azure-synapse-analytics-day-master.zip")

#unziping folder
function Expand-ZIPFile($file, $destination)
{
$shell = new-object -com shell.application
$zip = $shell.NameSpace($file)
foreach($item in $zip.items())
{
$shell.Namespace($destination).copyhere($item)
}
}
Expand-ZIPFile -File "C:\azure-synapse-analytics-day-master.zip" -Destination "C:\LabFiles\"
New-Item -ItemType Directory -Path "C:\LabFiles" -Force -ErrorAction SilentlyContinue | Out-Null
. C:\LabFiles\AzureCreds.ps1 2>$null

$AppID          = $env:AppID
$AppSecret      = $env:AppSecret
$azuserobjectid = $env:azuserobjectid

$securePassword = $AppSecret | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential -ArgumentList $AppID, $securePassword

Write-Host "Connecting to Azure with Service Principal..."
Connect-AzAccount -ServicePrincipal -Credential $cred -Tenant $AzureTenantID -Subscription $AzureSubscriptionID | Out-Null

$rgname= $resourceGroupName = (Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "*Synapse-AIAD*" }).ResourceGroupName

if ( $rgname -eq "Synapse-AIAD")
{

$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/synapse-tech-immersion/test-template/Automation1_new1.zip","C:\Automation1.zip")

#unziping folder
function Expand-ZIPFile($file, $destination)
{
$shell = new-object -com shell.application
$zip = $shell.NameSpace($file)
foreach($item in $zip.items())
{
$shell.Namespace($destination).copyhere($item)
}
}
Expand-ZIPFile -File "C:\Automation1.zip" -Destination "C:\LabFiles\"

}
else
{
Write-Host "Resource group name does not match Synapse-AIAD"
}

$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/synapse-tech-immersion/test-template/validate.ps1","C:\LabFiles\validate.ps1")

$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/synapse-tech-immersion/test-template/validationscript.psm1","C:\LabFiles\validationscript.psm1")

$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/synapse-tech-immersion/test-template/datastore.ps1","C:\LabFiles\datastore.ps1")


$LabFilesDirectory = "C:\LabFiles"

$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/synapse-tech-immersion/test-template/templateandstorage.ps1","C:\LabFiles\templateandstorage.ps1")

$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/synapse-tech-immersion/scripts/automation.bat","C:\LabFiles\automation.bat")
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/synapse-tech-immersion/scripts/export.bat","C:\LabFiles\export.bat")

#Install synapse modules
Install-PackageProvider NuGet -Force
Import-Module Az.Synapse -Force

. C:\LabFiles\AzureCreds.ps1

$AppID          = $env:AppID
$AppSecret      = $env:AppSecret
$azuserobjectid = $env:azuserobjectid

$securePassword = $AppSecret | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential -ArgumentList $AppID, $securePassword

Write-Host "Connecting to Azure with Service Principal..."
Connect-AzAccount -ServicePrincipal -Credential $cred -Tenant $AzureTenantID -Subscription $AzureSubscriptionID | Out-Null

$resourceGroupName = (Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "*Synapse-AIAD*" }).ResourceGroupName
$deploymentId =  (Get-AzResourceGroup -Name $resourceGroupName).Tags["DeploymentId"]

# Template deployment
$url = "https://experienceazure.blob.core.windows.net/templates/synapse-tech-immersion/test-template/deploy-synapse-parameters.json"
$output = "c:\LabFiles\parameters.json";
$wclient = New-Object System.Net.WebClient;
$wclient.CachePolicy = new-object System.Net.Cache.RequestCachePolicy([System.Net.Cache.RequestCacheLevel]::NoCacheNoStore);
$wclient.Headers.Add("Cache-Control", "no-cache");
$wclient.DownloadFile($url, $output)
(Get-Content -Path "c:\LabFiles\parameters.json") | ForEach-Object {$_ -Replace "GET-AZUSER-PASSWORD", "$AzurePassword"} | Set-Content -Path "c:\LabFiles\parameters.json"
(Get-Content -Path "c:\LabFiles\parameters.json") | ForEach-Object {$_ -Replace "GET-DEPLOYMENT-ID", "$DeploymentID"} | Set-Content -Path "c:\LabFiles\parameters.json"
(Get-Content -Path "c:\LabFiles\parameters.json") | ForEach-Object {$_ -Replace "GET-AZUSER-UPN", "$AzureUserName "} | Set-Content -Path "c:\LabFiles\parameters.json"
(Get-Content -Path "c:\LabFiles\parameters.json") | ForEach-Object {$_ -Replace "GET-AZUSER-OBJECTID", "$azuserobjectid"} | Set-Content -Path "c:\LabFiles\parameters.json"

Write-Host "Starting main deployment." -ForegroundColor Green -Verbose
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateUri "https://experienceazure.blob.core.windows.net/templates/synapse-tech-immersion/test-template/deploy-synapse.json" -TemplateParameterFile "c:\LabFiles\parameters.json"


#Download setup script
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/synapse-tech-immersion/test-template/01-environment-setup.ps1","C:\LabFiles\01-environment-setup.ps1")

#Download psm file
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/mcw-azure-synapse-analytics-and-ai/scripts/environment-automation.psm1","C:\LabFiles\environment-automation.psm1")

cd 'C:\LabFiles'
./01-environment-setup.ps1

Start-Sleep -Seconds 5

Enable-CloudLabsEmbeddedShadow $AdminUsername $trainerUserName $trainerUserPassword


#Enable Autologon
$AutoLogonRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $AutoLogonRegPath -Name "AutoAdminLogon" -Value "1" -type String 
Set-ItemProperty -Path $AutoLogonRegPath -Name "DefaultUsername" -Value "$($env:ComputerName)\demouser" -type String  
Set-ItemProperty -Path $AutoLogonRegPath -Name "DefaultPassword" -Value "$adminPassword" -type String
Set-ItemProperty -Path $AutoLogonRegPath -Name "AutoLogonCount" -Value "1" -type DWord

#checkdeployment
$status = (Get-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -Name "deploy-synapse").ProvisioningState
$status
if ($status -eq "Succeeded")
{
 
    $Validstatus="Pending"  ##Failed or Successful at the last step
    $Validmessage="Main Deployment is successful, logontask is pending"

 # Scheduled Task
$Trigger= New-ScheduledTaskTrigger -AtLogOn
$User= "$($env:ComputerName)\demouser" 
$Action= New-ScheduledTaskAction -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\Powershell.exe" -Argument "-executionPolicy Unrestricted -File $LabFilesDirectory\templateandstorage.ps1"
Register-ScheduledTask -TaskName "Setup" -Trigger $Trigger -User $User -Action $Action -RunLevel Highest -Force 

}
else {
    Write-Warning "Validation Failed - see log output"
    $Validstatus="Failed"  ##Failed or Successful at the last step
    $Validmessage="ARM template Deployment Failed"
      }

CloudlabsManualAgent setStatus

Stop-Transcript
Start-Sleep -Seconds 5
Restart-Computer -Force
