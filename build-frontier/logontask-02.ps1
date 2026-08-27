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

sleep 5
https://experienceazure.blob.core.windows.net/templates/tf/frontier-firm-productivity-workiq-copilot-agents/MsIQ-cplt-agntsfrntr-post-build-SPLabs.zip
$WebClient = New-Object System.Net.WebClient
 
# Create folder if it doesn't exist
New-Item -ItemType Directory -Path "C:\LabFiles" -Force | Out-Null
 
# Download ZIP
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/tf/frontier-firm-productivity-workiq-copilot-agents/MsIQ-cplt-agntsfrntr-post-build-SPLabs.zip", "C:\LabFiles\MsIQ-cplt-agntsfrntr-post-build-SPLabs.zip")
 
# Extract ZIP into C:\LabFiles
Expand-Archive -Path "C:\LabFiles\MsIQ-cplt-agntsfrntr-post-build-SPLabs.zip" -DestinationPath "C:\LabFiles" -Force
 
# Delete ZIP after extraction
Remove-Item "C:\LabFiles\MsIQ-cplt-agntsfrntr-post-build-SPLabs.zip" -Force

sleep 5
choco install visualstudio2022community -y

Unregister-ScheduledTask -TaskName "logontask" -Confirm:$false 

Restart-Computer -Force 

Stop-Transcript
