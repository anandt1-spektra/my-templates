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

InstallVSCode

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

sleep 5
choco upgrade nodejs-lts -y

choco --version

choco upgrade vscode -y

code

sleep 10
code --install-extension TeamsDevApp.ms-teams-vscode-extension

code --install-extension ms-vscode.vscode-typescript-next

sleep 5
choco install visualstudio2022community -y

Stop-Transcript
 
Restart-Computer -Force
