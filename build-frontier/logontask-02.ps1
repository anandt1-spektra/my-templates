Set-ExecutionPolicy -ExecutionPolicy bypass -Force
Start-Transcript -Path C:\WindowsAzure\Logs\CloudLabsLogOnTask.txt -Append
Write-Host "Logon-task-started" 

$commonscriptpath = "C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension\1.10.*\Downloads\0\cloudlabs-common\cloudlabs-windows-functions.ps1"
. $commonscriptpath

#installing extensions to vscode
choco install vscode-code-runner

#code --install-extension ms-toolsai.jupyter
code --install-extension TeamsDevApp.ms-teams-vscode-extension
code --install-extension ms-vscode.vscode-typescript-next

code --install-extension esbenp.prettier-vscode
code --install-extension dbaeumer.vscode-eslint

sleep 10

# Locate Visual Studio Installer
$vsInstaller = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

if (!(Test-Path $vsInstaller)) {
    Write-Host "Visual Studio Installer not found." -ForegroundColor Red
    exit 1
}

if (!(Test-Path $vsWhere)) {
    Write-Host "vswhere.exe not found." -ForegroundColor Red
    exit 1
}

# Find Visual Studio Community installation path
$installPath = & $vsWhere -latest -products * -property installationPath

if (:IsNullOrWhiteSpace($installPath)) {
    Write-Host "Visual Studio Community 2022 not found." -ForegroundColor Red
    exit 1
}

Write-Host "Visual Studio found at:" $installPath -ForegroundColor Green

# Install required workloads
& $vsInstaller modify `
    --installPath $installPath `
    --add Microsoft.VisualStudio.Workload.NetWeb `
    --add Microsoft.VisualStudio.Workload.Node `
    --passive `
    --norestart

# Install Microsoft 365 Agents Toolkit component
& $vsInstaller modify `
    --installPath $installPath `
    --add Microsoft.VisualStudio.Component.TeamsToolkit `
    --passive `
    --norestart

Write-Host "Installation request submitted." -ForegroundColor Green

Unregister-ScheduledTask -TaskName "logontask" -Confirm:$false 

Restart-Computer -Force 

Stop-Transcript