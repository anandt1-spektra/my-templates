## BEGIN: PLATFORM INSERT START
param($Request, $TriggerMetadata)

# Unwraps AggregateException / nested InnerExceptions and Graph error bodies so the
# real cause is surfaced instead of the useless "One or more errors occurred."
function Resolve-ErrorMessage {
    param($ErrorRecord)
    $parts = New-Object System.Collections.Generic.List[string]
    $ex = $ErrorRecord.Exception
    while ($ex) {
        if ($ex -is [System.AggregateException]) {
            foreach ($ie in $ex.Flatten().InnerExceptions) { [void]$parts.Add($ie.Message) }
        }
        else {
            [void]$parts.Add($ex.Message)
        }
        $ex = $ex.InnerException
    }
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        [void]$parts.Add($ErrorRecord.ErrorDetails.Message)
    }
    return (($parts | Where-Object { $_ } | Select-Object -Unique) -join " || ")
}

try
{
$sysAddedUsername = $Request.Body.sysAddedUsername
$sysAddedPassword = $Request.Body.sysAddedPassword | ConvertTo-SecureString -asPlainText -Force
$sysAddedSubscriptionId = $Request.Body.sysAddedSubscriptionId
$sysAddedTenantId = $Request.Body.sysAddedTenantId
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $sysAddedUsername, $sysAddedPassword

# Connect-AzAccount can throw a transient AggregateException ("One or more errors
# occurred."). It isn't used for the seeding work (that runs off the ROPC token),
# so retry it and surface the real error if it keeps failing.
$azConnected = $false
$azAttempt   = 0
while (-not $azConnected -and $azAttempt -lt 5) {
    try {
        $azAttempt++
        Connect-AzAccount -ServicePrincipal -Credential $Credential -Tenant $sysAddedTenantId -ErrorAction Stop | Out-Null
        $azConnected = $true
    }
    catch {
        Write-Host "Connect-AzAccount attempt $azAttempt failed: $(Resolve-ErrorMessage $_)"
        if ($azAttempt -lt 5) { Start-Sleep -Seconds 15 } else { throw }
    }
}
## END: PLATFORM INSERT END

## BEGIN: VARIABLES SECTION INSERT START
$azureuser = $Request.Body.azureuser
$SubscriptionId = $Request.Body.SubscriptionId
$deploymentlD = $Request.Body.deploymentlD
$azureuseremail = $Request.Body.azureuseremail
$azureuserpassword = $Request.Body.azureuserpassword
## END: VARIABLES SECTION INSERT END

try {

    # --------------------------------------------
    # TUNABLES
    # --------------------------------------------
    # Timezone label applied to due/completed times. Matches the spec's examples.
    # Only affects how the wall-clock time is interpreted; the day offsets are what
    # matter for "due in the next few days" / "completed in the last week".
    $taskTimeZone = "Pacific Standard Time"


    # --------------------------------------------
    # DELEGATED TOKEN via ROPC as the ODL user (Megan)
    # --------------------------------------------
    # To Do has NO application permission, so we sign in AS Megan (the ODL user)
    # with the password already passed to this Function, and use a delegated
    # Tasks.ReadWrite token. Requires the app to be enabled as a public client and
    # granted Tasks.ReadWrite (delegated) with admin consent.
    $odlUser = $azureuser
    if ([string]::IsNullOrWhiteSpace($odlUser) -or ($odlUser -notmatch "@")) {
        throw "azureuser is missing or not a valid email; cannot sign in as the ODL user."
    }
    if ([string]::IsNullOrWhiteSpace($azureuserpassword)) {
        throw "azureuserpassword is empty; ROPC sign-in as the ODL user needs it."
    }

    $tokenUrl  = "https://login.microsoftonline.com/$sysAddedTenantId/oauth2/v2.0/token"
    $ropcBody  = @{
        grant_type    = "password"
        client_id     = $sysAddedUsername            # the app's client id
        client_secret = $Request.Body.sysAddedPassword  # app is a confidential client (AADSTS7000218)
        username      = $odlUser                      # ODL user = Megan
        password      = $azureuserpassword
        scope         = "https://graph.microsoft.com/.default"
    }

    $accessToken  = $null
    $tokenAttempt = 0
    while (-not $accessToken -and $tokenAttempt -lt 5) {
        try {
            $tokenAttempt++
            Write-Host "Getting delegated (ROPC) token as $odlUser - attempt $tokenAttempt"
            $tokenResponse = Invoke-RestMethod -Method POST -Uri $tokenUrl -Body $ropcBody -ContentType "application/x-www-form-urlencoded"
            $accessToken = $tokenResponse.access_token
            Write-Host "Delegated token acquired"
        }
        catch {
            Write-Host "ROPC token attempt failed: $(Resolve-ErrorMessage $_)"
            if ($tokenAttempt -lt 5) { Start-Sleep -Seconds 10 } else { throw "Unable to acquire delegated token as $odlUser (check client_secret, password, Tasks.ReadWrite delegated consent, and ROPC/MFA settings)" }
        }
    }


    # --------------------------------------------
    # GENERIC GRAPH CALL (status-aware retry)
    # --------------------------------------------
    function Invoke-Graph {
        param(
            [string]$Method,
            [string]$Uri,
            $Body = $null,
            [int[]]$RetryOn = @(429,500,502,503,504),
            [int]$MaxRetries = 3,
            [int]$DelaySeconds = 5
        )
        for ($a = 1; $a -le $MaxRetries; $a++) {
            try {
                $params = @{
                    Method      = $Method
                    Uri         = $Uri
                    Headers     = @{ Authorization = "Bearer $accessToken" }
                    ContentType = "application/json"
                }
                if ($null -ne $Body) { $params.Body = ($Body | ConvertTo-Json -Depth 12) }
                return Invoke-RestMethod @params
            }
            catch {
                $status = $null
                try { $status = [int]$_.Exception.Response.StatusCode } catch { }
                $retryable = ($RetryOn -contains $status) -or ($null -eq $status)
                if (($a -lt $MaxRetries) -and $retryable) {
                    Write-Host "  Graph $Method -> status=$status, retry $a in ${DelaySeconds}s"
                    Start-Sleep -Seconds $DelaySeconds
                    continue
                }
                throw
            }
        }
    }


    # --------------------------------------------
    # TARGET LIST = Megan's built-in "Tasks" (defaultList)
    # --------------------------------------------
    $lists  = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/me/todo/lists"
    $listId = ($lists.value | Where-Object { $_.wellknownListName -eq "defaultList" } | Select-Object -First 1).id
    if (-not $listId) { $listId = ($lists.value | Select-Object -First 1).id }   # fallback
    if (-not $listId) { throw "Could not find a To Do list for $odlUser" }
    Write-Host "Target list id: $listId"


    # --------------------------------------------
    # RUN-DAY ANCHOR (UTC date; times are wall-clock in $taskTimeZone)
    # --------------------------------------------
    $runDate = [DateTime]::UtcNow.Date     # R

    function Format-TaskTime {
        param([datetime]$Dt)
        return $Dt.ToString("yyyy-MM-ddTHH:mm:ss")
    }


    # --------------------------------------------
    # TASK DATA (from the spec)
    # --------------------------------------------
    # Open: due in the next few days. Completed: done within the last week.
    $openTasks = @(
        @{ Title = "Sign off Beacon customer hold comms";        DueOffset = 1; Hour = 9 }   # R+1  Task1 Needs a decision
        @{ Title = "Approve vendor evaluation criteria";          DueOffset = 2; Hour = 9 }   # R+2  Task1 Needs a decision
        @{ Title = "Chase Finance for Q3 actuals - Summit pack";  DueOffset = 3; Hour = 9 }   # R+3  Task1 Upcoming
    )
    $completedTasks = @(
        @{ Title = "Finalise Beacon GA hold decision memo";       DoneOffset = 6; Hour = 17 } # R-6  Task2 Accomplished
        @{ Title = "Update portfolio workbook post-decision";     DoneOffset = 5; Hour = 17 } # R-5  Task2 Accomplished
    )

    $failures = New-Object System.Collections.Generic.List[string]
    $created  = 0

    # ---- OPEN tasks ----
    foreach ($t in $openTasks) {
        try {
            $due = $runDate.AddDays($t.DueOffset).AddHours($t.Hour)
            $body = @{
                title       = $t.Title
                status      = "notStarted"
                dueDateTime = @{ dateTime = (Format-TaskTime $due); timeZone = $taskTimeZone }
            }
            Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/me/todo/lists/$listId/tasks" -Body $body | Out-Null
            $created++
            Write-Host "Created OPEN task: $($t.Title) (due R+$($t.DueOffset))"
        }
        catch {
            $msg = Resolve-ErrorMessage $_
            Write-Host "OPEN task FAILED [$($t.Title)]: $msg"
            [void]$failures.Add("open [$($t.Title)] -> $msg")
        }
    }

    # ---- COMPLETED tasks (create, then PATCH to completed with a back-dated completedDateTime) ----
    foreach ($t in $completedTasks) {
        try {
            # 1) create the task
            $createBody = @{ title = $t.Title }
            $task = Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/me/todo/lists/$listId/tasks" -Body $createBody

            # 2) mark completed with a back-dated completion time
            $done = $runDate.AddDays(-$t.DoneOffset).AddHours($t.Hour)
            $patchBody = @{
                status            = "completed"
                completedDateTime = @{ dateTime = (Format-TaskTime $done); timeZone = $taskTimeZone }
            }
            Invoke-Graph -Method PATCH -Uri "https://graph.microsoft.com/v1.0/me/todo/lists/$listId/tasks/$($task.id)" -Body $patchBody | Out-Null
            $created++
            Write-Host "Created COMPLETED task: $($t.Title) (completed R-$($t.DoneOffset))"
        }
        catch {
            $msg = Resolve-ErrorMessage $_
            Write-Host "COMPLETED task FAILED [$($t.Title)]: $msg"
            [void]$failures.Add("completed [$($t.Title)] -> $msg")
        }
    }


    # --------------------------------------------
    # RESPONSE
    # --------------------------------------------
    $expected = $openTasks.Count + $completedTasks.Count
    $summary  = "tasks created: $created/$expected; failures: $($failures.Count)"
    Write-Host $summary

    if ($failures.Count -eq 0) {
        $response = @{
            Status       = "Succeeded"
            Message      = "To Do seeding complete. $summary"
            ODLUser      = $odlUser
            TasksCreated = $created
        } | ConvertTo-Json
    }
    else {
        $response = @{
            Status       = "Failed"
            Message      = $summary
            ODLUser      = $odlUser
            TasksCreated = $created
            Failures     = ($failures -join " || ")
        } | ConvertTo-Json
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body       = $response
    })

}
catch {
    $realError = Resolve-ErrorMessage $_
    Write-Host "Function execution failed: $realError"
    $response = @{
        Status  = "Failed"
        Message = $realError
    } | ConvertTo-Json

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body       = $response
    })
}
}
catch
{
    $realError = Resolve-ErrorMessage $_
    $message = @{Status = "Failed"; Message = $realError; InvocationId = $TriggerMetadata.InvocationId} | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body = $message})
}
