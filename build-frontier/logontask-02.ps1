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

Unregister-ScheduledTask -TaskName "logontask" -Confirm:$false 

Restart-Computer -Force 

Stop-Transcript