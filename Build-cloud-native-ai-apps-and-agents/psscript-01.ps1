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
    $DeploymentID,
    [string]
    $vmAdminUsername,
    [string]
    $vmAdminPassword,
    [string]
    $trainerUserName,
    [string]
    $trainerUserPassword
)
 
Start-Transcript -Path C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt -Append
[Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls" 

#Import Common Functions
$path = pwd
$path=$path.Path
$commonscriptpath = "$path" + "\cloudlabs-common\cloudlabs-windows-functions.ps1"
. $commonscriptpath
 
# Run Imported functions from cloudlabs-windows-functions.ps1
WindowsServerCommon

CreateCredFile $AzureUserName $AzurePassword $AzureTenantID $AzureSubscriptionID $DeploymentID 

Enable-CloudLabsEmbeddedShadow $vmAdminUsername $trainerUserName $trainerUserPassword

# DownloadFiles
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://raw.githubusercontent.com/anandt1-spektra/my-templates/refs/heads/main/Build-cloud-native-ai-apps-and-agents/logontask-01.ps1", "C:\Packages\logontask-01.ps1")
 
#Enable Autologon
$AutoLogonRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $AutoLogonRegPath -Name "AutoAdminLogon" -Value "1" -type String
Set-ItemProperty -Path $AutoLogonRegPath -Name "DefaultUsername" -Value "$($env:ComputerName)\azureuser" -type String  
Set-ItemProperty -Path $AutoLogonRegPath -Name "DefaultPassword" -Value "$adminPassword" -type String
Set-ItemProperty -Path $AutoLogonRegPath -Name "AutoLogonCount" -Value "1" -type DWord
 
# Scheduled Task to Run PostConfig.ps1 screen on logon
$Trigger= New-ScheduledTaskTrigger -AtLogOn
$User= "$($env:ComputerName)\azureuser"
$Action= New-ScheduledTaskAction -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\Powershell.exe" -Argument "-executionPolicy Unrestricted -WindowStyle Hidden -File C:\Packages\logontask-01.ps1"
Register-ScheduledTask -TaskName "logontask" -Trigger $Trigger -User $User -Action $Action -RunLevel Highest -Force
Set-ExecutionPolicy -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue

# Cli
choco install azure-cli -y

# Git
choco install git -y

# GitHub CLI
choco install gh -y

# Kubernetes CLI
choco install kubernetes-cli -y

# Helm
choco install kubernetes-helm -y

# Terraform
choco install terraform -y

# jq
choco install jq -y

#zsh
choco install msys2 -y

sleep 5
choco upgrade nodejs-lts -y

choco --version

choco upgrade vscode -y

Stop-Transcript
 
Restart-Computer -Force
