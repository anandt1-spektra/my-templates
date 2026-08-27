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
Function CloneLabFiles
{
    $GitHubToken = ""

    $RepoUrl     = "https://$GitHubToken@github.com/CloudLabsAI-Azure/MsIQ-cplt-agntsfrntr.git"
    $Branch      = "post-build-SPLabs"
    $SourcePath  = "Lab Files"
    $Destination = "C:\Lab Files"
    $TempDir     = Join-Path $env:TEMP "MsIQ-clone-$(Get-Random)"

    # Ensure git is available; install via choco if missing
    if (-not (Get-Command git -ErrorAction SilentlyContinue))
    {
        choco install git -y --no-progress
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")
    }

    Write-Host "Cloning '$SourcePath' from private repository..."

    # Shallow, blobless, sparse clone
    git clone `
        --depth 1 `
        --filter=blob:none `
        --sparse `
        --branch $Branch `
        $RepoUrl `
        $TempDir

    if ($LASTEXITCODE -ne 0)
    {
        throw "Git clone failed. Verify the PAT has access to the repository."
    }

    Push-Location $TempDir

    git sparse-checkout init --cone
    git sparse-checkout set "$SourcePath"

    Pop-Location

    if (-not (Test-Path $Destination))
    {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    Copy-Item `
        -Path (Join-Path $TempDir $SourcePath | Join-Path -ChildPath "*") `
        -Destination $Destination `
        -Recurse `
        -Force

    Remove-Item $TempDir -Recurse -Force

    Write-Host "Lab Files copied successfully to $Destination"
}
CloneLabFiles

sleep 5
choco install visualstudio2022community -y

Unregister-ScheduledTask -TaskName "logontask" -Confirm:$false 

Restart-Computer -Force 

Stop-Transcript
