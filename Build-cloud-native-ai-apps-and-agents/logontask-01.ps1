Set-ExecutionPolicy -ExecutionPolicy bypass -Force
Start-Transcript -Path C:\WindowsAzure\Logs\CloudLabsLogOnTask.txt -Append
Write-Host "Logon-task-started" 

$commonscriptpath = "C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension\1.10.*\Downloads\0\cloudlabs-common\cloudlabs-windows-functions.ps1"
. $commonscriptpath

#code
code --install-extension ms-kubernetes-tools.vscode-aks-tools
code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools

code --install-extension ms-azuretools.vscode-containers

sleep 5

Unregister-ScheduledTask -TaskName "logontask" -Confirm:$false 

Restart-Computer -Force 

Stop-Transcript