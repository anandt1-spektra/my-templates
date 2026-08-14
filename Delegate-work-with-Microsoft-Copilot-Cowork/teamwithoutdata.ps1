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
# occurred."). It isn't used for the seeding work (that runs off the Graph token),
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
    # Set to 1 to validate a single chat end-to-end (spec recommends this before
    # seeding all seven). 0 = seed everything.
    $maxChatsToSeed = 0
    # Timezone for calendar events. UTC keeps it simple and still satisfies the
    # "next three days" / "meetings I led" checks. Change to e.g. "India Standard Time"
    # or "Pacific Standard Time" if you want the times in a specific zone.
    $eventTimeZone  = "UTC"


    # --------------------------------------------
    # GRAPH APP-ONLY TOKEN (with retry)
    # --------------------------------------------
    $tokenUrl = "https://login.microsoftonline.com/$sysAddedTenantId/oauth2/v2.0/token"
    $tokenBody = @{
        client_id     = $sysAddedUsername
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $Request.Body.sysAddedPassword
        grant_type    = "client_credentials"
    }

    $accessToken = $null
    $tokenAttempt = 0
    while (-not $accessToken -and $tokenAttempt -lt 5) {
        try {
            $tokenAttempt++
            Write-Host "Generating Graph token - attempt $tokenAttempt"
            $tokenResponse = Invoke-RestMethod -Method POST -Uri $tokenUrl -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
            $accessToken = $tokenResponse.access_token
            Write-Host "Graph token generated"
        }
        catch {
            Write-Host "Token attempt failed: $(Resolve-ErrorMessage $_)"
            if ($tokenAttempt -lt 5) { Start-Sleep -Seconds 10 } else { throw "Unable to generate Graph token" }
        }
    }


    # --------------------------------------------
    # TENANT DOMAIN + USERS  (Megan = ODL user)
    # --------------------------------------------
    $odlUser = $azureuser
    if ([string]::IsNullOrWhiteSpace($odlUser) -or ($odlUser -notmatch "@")) {
        throw "azureuser is missing or not a valid email; cannot resolve tenant domain."
    }
    $domain = ($odlUser.Split("@")[1]).Trim()
    Write-Host "Tenant domain: $domain | ODL (Megan): $odlUser"

    # UPN prefixes -> resolved to { Upn; Id }. Megan_Bowen maps to the ODL user.
    $prefixes = @(
        "Megan_Bowen","Isaiah_Langer","Alex_Wilbur","Nestor_Wilke",
        "Joni_Sherman","Allan_Deyoung","Diego_Siciliani","Patti_Fernandez"
    )
    $U = @{}
    foreach ($p in $prefixes) {
        $upn = if ($p -eq "Megan_Bowen") { $odlUser } else { "$p@$domain" }
        $U[$p] = @{ Upn = $upn; Id = $null }
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
                    Write-Host "  Graph $Method $Uri -> status=$status, retry $a in ${DelaySeconds}s"
                    Start-Sleep -Seconds $DelaySeconds
                    continue
                }
                throw
            }
        }
    }


    # --------------------------------------------
    # RESOLVE USER IDS
    # --------------------------------------------
    $failures = New-Object System.Collections.Generic.List[string]

    foreach ($p in $prefixes) {
        try {
            $resolvedUser = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($U[$p].Upn)"
            $U[$p].Id = $resolvedUser.id
            Write-Host "Resolved $p -> $($resolvedUser.id)"
        }
        catch {
            $msg = Resolve-ErrorMessage $_
            Write-Host "FAILED to resolve $($U[$p].Upn): $msg"
            [void]$failures.Add("resolve $($U[$p].Upn) -> $msg")
        }
    }


    # --------------------------------------------
    # RUN-DAY ANCHORS (UTC)
    # --------------------------------------------
    $nowUtc  = [DateTime]::UtcNow
    $runDate = $nowUtc.Date            # midnight UTC today = R


    # ============================================
    # 7 GROUP CHATS (app-only import)
    # ============================================
    # Offset = R-x conversation day. Topic $null => leave blank (Megan's 3).
    $chats = @(
        @{ Name="Nestor, Patti";        Topic=$null;             Offset=2; Members=@("Megan_Bowen","Nestor_Wilke","Patti_Fernandez"); Messages=@(
            @{ From="Nestor_Wilke";    Text="Megan - vendor consolidation is now blocking. We need your call on the evaluation criteria before we can shortlist the final two." }
            @{ From="Patti_Fernandez"; Text="Agreed. Megan, can you get to this before the Monday review? Renewal penalty exposure starts in October." }
            @{ From="Megan_Bowen";     Text="Understood - I'll review the criteria doc and come back with a decision this week." }
            @{ From="Nestor_Wilke";    Text="Separately, FYI: the passkey pilot expanded to all of Sales this week and is going smoothly so far." }
        )}

        @{ Name="Allan, Diego, Isaiah"; Topic=$null;             Offset=1; Members=@("Megan_Bowen","Allan_Deyoung","Diego_Siciliani","Isaiah_Langer"); Messages=@(
            @{ From="Allan_Deyoung";    Text="Beacon remediation sprint day 2 - 3 of 11 defect cases closed. On track for the 14 August review." }
            @{ From="Diego_Siciliani";  Text="Heads-up: Mobile v3 beta ships on the 21st, so QA capacity will be tight that week." }
            @{ From="Isaiah_Langer";    Text="Reminder for everyone - the vendor decision review is on the 11th. Prep doc goes out Friday." }
            @{ From="Megan_Bowen";      Text="Thanks all. I'll have the criteria signed off before the 11th so we're not blocked." }
        )}

        @{ Name="Alex, Allan, Diego";   Topic=$null;             Offset=2; Members=@("Megan_Bowen","Alex_Wilbur","Allan_Deyoung","Diego_Siciliani"); Messages=@(
            @{ From="Alex_Wilbur";      Text="Atlas W8 numbers are in - best week yet. The monthly read-out lands on the first business day of September." }
            @{ From="Allan_Deyoung";    Text="Nice results. Megan - do you want Atlas included as a good-news slide in the Summit pack?" }
            @{ From="Diego_Siciliani";  Text="Also flagging: the Summit prep session is Thursday, invites going out today." }
        )}

        @{ Name="Project Helios";       Topic="Project Helios";  Offset=3; Members=@("Joni_Sherman","Allan_Deyoung","Diego_Siciliani"); Messages=@(
            @{ From="Allan_Deyoung";    Text="Helios milestone M3 completed and signed off. No open defects." }
            @{ From="Joni_Sherman";     Text="Great - that keeps us on track for the September pilot. Next milestone is Pilot start on 9 Sep." }
            @{ From="Diego_Siciliani";  Text="Throughput testing came back above target. Nothing blocking from my side." }
        )}

        @{ Name="Project Griffin";      Topic="Project Griffin"; Offset=2; Members=@("Joni_Sherman","Diego_Siciliani","Isaiah_Langer"); Messages=@(
            @{ From="Diego_Siciliani";  Text="Griffin budget revision v3 is uploaded. We need sign-off by 15 August or the timeline is at risk." }
            @{ From="Isaiah_Langer";    Text="Finance has questions on the contractor line. Could slip a few days." }
            @{ From="Joni_Sherman";     Text="Flagging Griffin as at-risk until the revised budget is approved. Owner remains Diego." }
        )}

        @{ Name="Project Nimbus";       Topic="Project Nimbus";  Offset=2; Members=@("Joni_Sherman","Isaiah_Langer","Allan_Deyoung"); Messages=@(
            @{ From="Isaiah_Langer";    Text="Nimbus integration testing is still blocked - we've been waiting on API credentials from the vendor for two weeks." }
            @{ From="Allan_Deyoung";    Text="Two test tasks are blocked and one is now overdue as a result." }
            @{ From="Joni_Sherman";     Text="Escalating the vendor credentials. Nimbus is RED until integration testing can restart." }
        )}

        @{ Name="Atlas Launch";         Topic="Atlas Launch";    Offset=2; Members=@("Alex_Wilbur","Diego_Siciliani","Allan_Deyoung"); Messages=@(
            @{ From="Alex_Wilbur";      Text="W8 in the books - new highs on signups (2,895) and conversion (14.5%). Metrics workbook is updated in my files." }
            @{ From="Diego_Siciliani";  Text="Enterprise is now roughly 49% of launch-to-date revenue from about 5% of customers. The enterprise motion is clearly working." }
            @{ From="Allan_Deyoung";    Text="Watch item: support ticket volume is tracking up in line with activations. Capacity review is booked." }
            @{ From="Alex_Wilbur";      Text="Noted. Status update for the weekly sync goes out Thursday as usual." }
        )}
    )

    function Seed-Chat {
        param($chat)

        # Validate all members resolved
        foreach ($p in $chat.Members) {
            if (-not $U[$p].Id) { throw "member $p ($($U[$p].Upn)) did not resolve to an id" }
        }

        # 1) Create the group chat (Chat.Create)
        $members = @()
        foreach ($p in $chat.Members) {
            $members += @{
                "@odata.type"     = "#microsoft.graph.aadUserConversationMember"
                roles             = @("owner")
                "user@odata.bind" = "https://graph.microsoft.com/v1.0/users('$($U[$p].Id)')"
            }
        }
        $createBody = @{ chatType = "group"; members = $members }
        if ($chat.Topic) { $createBody.topic = $chat.Topic }

        $created = Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/chats" -Body $createBody
        $chatId  = $created.id
        Write-Host "Created chat '$($chat.Name)' -> $chatId"

        # 2) startMigration - back-dates the chat to the conversation day 08:00
        $convDay     = $runDate.AddDays(-$chat.Offset)
        $chatCreated = $convDay.AddHours(8)   # 08:00:00.000 on the conversation day
        $startBody   = @{ conversationCreationDateTime = $chatCreated.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }
        Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/chats/$chatId/startMigration" -Body $startBody -RetryOn @(400,404,429,500,502,503,504) | Out-Null
        Write-Host "  startMigration ok (createdDateTime=$($startBody.conversationCreationDateTime))"

        # 3) Import each message in Seq order: 08:0N with N ms -> unique, ordered, > chat createdDateTime, past
        $seq = 0
        foreach ($m in $chat.Messages) {
            $seq++
            if (-not $U[$m.From].Id) { throw "sender $($m.From) did not resolve to an id" }
            $ts = $chatCreated.AddMinutes($seq).AddMilliseconds($seq)
            $msgBody = @{
                createdDateTime = $ts.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                from = @{ user = @{
                    id               = $U[$m.From].Id
                    userIdentityType = "aadUser"
                    "@odata.type"    = "#microsoft.graph.teamworkUserIdentity"
                } }
                body = @{ contentType = "text"; content = $m.Text }
            }
            # 404 right after startMigration can be transient; 409 = duplicate timestamp
            Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/chats/$chatId/messages" -Body $msgBody -RetryOn @(404,409,429,500,502,503,504) | Out-Null
            Write-Host "  msg $seq from $($m.From) imported"
        }

        # 4) completeMigration - makes the chat usable
        Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/chats/$chatId/completeMigration" -RetryOn @(400,404,429,500,502,503,504) | Out-Null
        Write-Host "  completeMigration ok"

        return $chatId
    }

    $chatsDone = 0
    $chatIndex = 0
    foreach ($chat in $chats) {
        $chatIndex++
        if (($maxChatsToSeed -gt 0) -and ($chatsDone -ge $maxChatsToSeed)) { break }
        try {
            Seed-Chat $chat | Out-Null
            $chatsDone++
        }
        catch {
            $msg = Resolve-ErrorMessage $_
            Write-Host "CHAT FAILED [$($chat.Name)]: $msg"
            [void]$failures.Add("chat [$($chat.Name)] -> $msg")
        }
    }


    # ============================================
    # CALENDAR EVENTS
    # ============================================
    function New-Event {
        param(
            [string]$OrganiserPrefix,
            [string]$Subject,
            [datetime]$StartDt,
            [int]$Minutes,
            [string[]]$AttendeePrefixes,
            [bool]$IsOnline = $false,
            $Recurrence = $null
        )
        $end = $StartDt.AddMinutes($Minutes)
        $attendees = @()
        foreach ($ap in $AttendeePrefixes) {
            $attendees += @{ emailAddress = @{ address = $U[$ap].Upn; name = ($ap -replace "_"," ") }; type = "required" }
        }
        $ev = @{
            subject = $Subject
            start   = @{ dateTime = $StartDt.ToString("yyyy-MM-ddTHH:mm:ss"); timeZone = $eventTimeZone }
            end     = @{ dateTime = $end.ToString("yyyy-MM-ddTHH:mm:ss");     timeZone = $eventTimeZone }
            attendees = $attendees
        }
        if ($IsOnline)    { $ev.isOnlineMeeting = $true; $ev.onlineMeetingProvider = "teamsForBusiness" }
        if ($Recurrence)  { $ev.recurrence = $Recurrence }

        return Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$($U[$OrganiserPrefix].Upn)/events" -Body $ev
    }

    # ---- Megan's 5 events (organiser = Megan because created in her calendar) ----
    $meganEvents = @(
        @{ Subject="Summit prep session";          Start=$runDate.AddDays(1).AddHours(10);            Min=45; Att=@("Nestor_Wilke","Diego_Siciliani");                 Online=$true  }  # R+1 Task 1
        @{ Subject="1:1 Megan / Patti";            Start=$runDate.AddDays(1).AddHours(15);            Min=30; Att=@("Patti_Fernandez");                                Online=$true  }  # R+1 Task 1
        @{ Subject="Beacon remediation check-in";  Start=$runDate.AddDays(2).AddHours(11);            Min=60; Att=@("Allan_Deyoung");                                  Online=$true  }  # R+2 Task 1
        @{ Subject="Beacon decision review";       Start=$runDate.AddDays(-6).AddHours(10);           Min=60; Att=@("Allan_Deyoung","Diego_Siciliani","Nestor_Wilke"); Online=$false }  # R-6 Task 2 (led)
        @{ Subject="Portfolio weekly";             Start=$runDate.AddDays(-3).AddHours(14);           Min=30; Att=@("Allan_Deyoung","Diego_Siciliani","Patti_Fernandez"); Online=$false } # R-3 Task 2 (led)
    )

    foreach ($e in $meganEvents) {
        try {
            New-Event -OrganiserPrefix "Megan_Bowen" -Subject $e.Subject -StartDt $e.Start -Minutes $e.Min -AttendeePrefixes $e.Att -IsOnline $e.Online | Out-Null
            Write-Host "Created Megan event: $($e.Subject)"
        }
        catch {
            $msg = Resolve-ErrorMessage $_
            Write-Host "EVENT FAILED [$($e.Subject)]: $msg"
            [void]$failures.Add("event [$($e.Subject)] -> $msg")
        }
    }

    # ---- Joni's recurring Weekly Project Sync (weekly Friday, online) ----
    try {
        # Anchor on the most recent Friday on/before ~R-21
        $anchor = $runDate.AddDays(-21)
        while ($anchor.DayOfWeek -ne [DayOfWeek]::Friday) { $anchor = $anchor.AddDays(-1) }
        $seriesStart = $anchor.AddHours(10)   # Friday 10:00

        $recurrence = @{
            pattern = @{ type = "weekly"; interval = 1; daysOfWeek = @("friday") }
            range   = @{
                type      = "endDate"
                startDate = $anchor.ToString("yyyy-MM-dd")
                endDate   = $runDate.AddDays(14).ToString("yyyy-MM-dd")
            }
        }

        New-Event -OrganiserPrefix "Joni_Sherman" -Subject "Weekly Project Sync" -StartDt $seriesStart -Minutes 30 `
                  -AttendeePrefixes @("Megan_Bowen","Allan_Deyoung","Diego_Siciliani") -IsOnline $true -Recurrence $recurrence | Out-Null
        Write-Host "Created Joni recurring series: Weekly Project Sync (from $($anchor.ToString('yyyy-MM-dd')))"
    }
    catch {
        $msg = Resolve-ErrorMessage $_
        Write-Host "EVENT FAILED [Weekly Project Sync]: $msg"
        [void]$failures.Add("event [Weekly Project Sync] -> $msg")
    }


    # ============================================
    # RESPONSE
    # ============================================
    $summary = "chats seeded: $chatsDone/$($chats.Count); failures: $($failures.Count)"
    Write-Host $summary

    if ($failures.Count -eq 0) {
        $response = @{
            Status      = "Succeeded"
            Message     = "Teams seeding complete. $summary"
            Domain      = $domain
            ODLUser     = $odlUser
            ChatsSeeded = $chatsDone
        } | ConvertTo-Json
    }
    else {
        $response = @{
            Status      = "Failed"
            Message     = $summary
            Domain      = $domain
            ODLUser     = $odlUser
            ChatsSeeded = $chatsDone
            Failures    = ($failures -join " || ")
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
