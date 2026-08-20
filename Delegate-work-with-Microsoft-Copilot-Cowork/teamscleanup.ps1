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
# occurred."). It isn't used for the cleanup work (that runs off the Graph token),
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
    # Master switches for what to wipe.
    $cleanupChats  = $true
    $cleanupEvents = $true
    # Graph allows only ~1 chat delete/sec/tenant, so pause between chat deletes.
    $chatDeleteDelaySeconds = 2
    # Chat discovery + deletion run entirely APP-ONLY:
    #   - list each user's chats via GET /users/{id}/chats  (needs Chat.Read.All or
    #     Chat.ReadBasic.All or Chat.ReadWrite.All application permission)
    #   - delete via DELETE /chats/{id}                     (needs Chat.ManageDeletion.All
    #     application permission, admin-consented)
    # This covers EVERY user's chats, not just the caller's, and needs no user login.
    $useDelegatedListing = $false   # leave off; per-user app-only listing is more complete

    # All seeded users - used for BOTH chat discovery and calendar cleanup.
    $allUserPrefixes = @(
        "Megan_Bowen","Isaiah_Langer","Alex_Wilbur","Nestor_Wilke",
        "Joni_Sherman","Allan_Deyoung","Diego_Siciliani","Patti_Fernandez"
    )


    # --------------------------------------------
    # GRAPH APP-ONLY TOKEN (with retry) - used for calendar deletes
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
    # GRAPH DELEGATED TOKEN - used for chat deletes
    # --------------------------------------------
    # Chat deletion requires the caller to be a tenant admin for the user who
    # created the chats. The seeding script created them under this delegated user.
    $delegatedToken = $null
    if ($cleanupChats -and $useDelegatedListing) {
        $delegatedUser = if ([string]::IsNullOrWhiteSpace($azureuseremail)) { $azureuser } else { $azureuseremail }
        $clientId = $sysAddedUsername
        $consentRequired = $false
        if ([string]::IsNullOrWhiteSpace($delegatedUser) -or [string]::IsNullOrWhiteSpace($azureuserpassword)) {
            throw "Chat cleanup enabled, but azureuseremail/azureuserpassword is missing."
        }

        $delegatedBody = @{
            client_id     = $clientId
            client_secret = $Request.Body.sysAddedPassword
            grant_type    = "password"
            username      = $delegatedUser
            password      = $azureuserpassword
            # Delegated token is only used to LIST chats, so Chat.ReadWrite is enough.
            # Chat deletion uses the app-only token (Chat.ManageDeletion.All application permission).
            scope         = "https://graph.microsoft.com/Chat.ReadWrite User.Read"
        }

        $delegatedAttempt = 0
        while (-not $delegatedToken -and $delegatedAttempt -lt 3) {
            try {
                $delegatedAttempt++
                Write-Host "Generating delegated Graph token - attempt $delegatedAttempt"
                $delegatedResponse = Invoke-RestMethod -Method POST -Uri $tokenUrl -Body $delegatedBody -ContentType "application/x-www-form-urlencoded"
                $delegatedToken = $delegatedResponse.access_token
                Write-Host "Delegated Graph token generated for $delegatedUser"
            }
            catch {
                $delegatedErr = Resolve-ErrorMessage $_
                if ($delegatedErr -match "AADSTS65001|consent_required") { $consentRequired = $true }
                Write-Host "Delegated token attempt failed: $delegatedErr"
                if ($delegatedAttempt -lt 3) { Start-Sleep -Seconds 5 }
            }
        }

        if (-not $delegatedToken) {
            if ($consentRequired) {
                $adminConsentUrl = "https://login.microsoftonline.com/$sysAddedTenantId/adminconsent?client_id=$clientId"
                throw "Consent required for delegated Graph scopes. Grant admin consent for this app in tenant $sysAddedTenantId and retry. Admin consent URL: $adminConsentUrl"
            }
            throw "Unable to generate delegated token for chat cleanup. Ensure delegated Graph permissions are consented and the user credentials are correct."
        }
    }


    # --------------------------------------------
    # TENANT DOMAIN
    # --------------------------------------------
    $odlUser = $azureuser
    if ([string]::IsNullOrWhiteSpace($odlUser) -or ($odlUser -notmatch "@")) {
        throw "azureuser is missing or not a valid email; cannot resolve tenant domain."
    }
    $domain = ($odlUser.Split("@")[1]).Trim()
    Write-Host "Tenant domain: $domain | cleanup caller: $odlUser"


    # --------------------------------------------
    # GENERIC GRAPH CALL (status-aware retry)
    # --------------------------------------------
    function Invoke-Graph {
        param(
            [string]$Method,
            [string]$Uri,
            $Body = $null,
            [string]$Token = $accessToken,
            [int[]]$RetryOn = @(429,500,502,503,504),
            [int]$MaxRetries = 3,
            [int]$DelaySeconds = 5
        )
        for ($a = 1; $a -le $MaxRetries; $a++) {
            try {
                $params = @{
                    Method      = $Method
                    Uri         = $Uri
                    Headers     = @{ Authorization = "Bearer $Token" }
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

    function Get-GraphStatus {
        param($ErrorRecord)
        $status = $null
        try { $status = [int]$ErrorRecord.Exception.Response.StatusCode } catch { }
        return $status
    }

    # Decodes a JWT payload so we can log which permissions the token actually carries.
    # App-only tokens expose permissions in the "roles" claim; delegated tokens in "scp".
    function Get-TokenClaims {
        param([string]$Jwt)
        try {
            $payload = $Jwt.Split(".")[1].Replace("-","+").Replace("_","/")
            switch ($payload.Length % 4) { 2 { $payload += "==" } 3 { $payload += "=" } }
            $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload))
            return ($json | ConvertFrom-Json)
        }
        catch { return $null }
    }

    # displayName fallback so a UPN-prefix mismatch still resolves.
    function Resolve-DirectoryUser {
        param([string]$Prefix, [string]$Upn)
        try {
            return Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$Upn"
        }
        catch {
            if ((Get-GraphStatus $_) -ne 404) { throw }
        }
        $displayName = $Prefix -replace "_"," "
        $escaped     = $displayName.Replace("'", "''")
        $f1 = [uri]::EscapeDataString("displayName eq '$escaped'")
        $r1 = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/users?`$filter=$f1&`$select=id,userPrincipalName,displayName"
        if ($r1.value -and @($r1.value).Count -ge 1) { return @($r1.value)[0] }
        $f2 = [uri]::EscapeDataString("startswith(displayName,'$escaped')")
        $r2 = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/users?`$filter=$f2&`$select=id,userPrincipalName,displayName"
        if ($r2.value -and @($r2.value).Count -ge 1) { return @($r2.value)[0] }
        return $null
    }

    $failures = New-Object System.Collections.Generic.List[string]


    # ============================================
    # CHAT CLEANUP - delete ALL chats (group, meeting, 1:1)
    # ============================================
    $chatsDeleted  = 0

    function Get-AllChatsForUsers {
        param([string[]]$Prefixes)
        $seen = @{}
        $all  = New-Object System.Collections.Generic.List[object]
        foreach ($p in $Prefixes) {
            $u = $null
            try { $u = Resolve-DirectoryUser -Prefix $p -Upn "$p@$domain" } catch { $u = $null }
            if (-not $u) { Write-Host "  skip chats for $p (no directory user)"; continue }
            $upn = if ($u.userPrincipalName) { $u.userPrincipalName } else { "$p@$domain" }

            $added = 0
            $uri = "https://graph.microsoft.com/v1.0/users/$upn/chats?`$top=50&`$select=id,topic,chatType"
            while ($uri) {
                try {
                    $resp = Invoke-Graph -Method GET -Uri $uri   # app-only token
                }
                catch {
                    $msg = Resolve-ErrorMessage $_
                    Write-Host "  list chats failed for $upn : $msg"
                    [void]$failures.Add("list chats $upn -> $msg")
                    break
                }
                foreach ($c in $resp.value) {
                    if (-not $seen.ContainsKey($c.id)) {
                        $seen[$c.id] = $true
                        [void]$all.Add($c)
                        $added++
                    }
                }
                $uri = $resp.'@odata.nextLink'
            }
            Write-Host "  $upn : +$added new chat(s)"
        }
        return $all
    }

    if ($cleanupChats) {
        Write-Host "Listing chats across ALL users (app-only)..."
        $allChats = @()
        try {
            $allChats = Get-AllChatsForUsers -Prefixes $allUserPrefixes
            Write-Host "Found $($allChats.Count) unique chat(s) to delete"
        }
        catch {
            $msg = Resolve-ErrorMessage $_
            Write-Host "FAILED to list chats: $msg"
            [void]$failures.Add("list chats -> $msg")
        }

        # Deletion is app-only and requires the Chat.ManageDeletion.All application permission.
        $chatDeleteToken = $accessToken

        # Diagnostic: show exactly what the delete token carries so a 403 is easy to explain.
        $claims  = Get-TokenClaims $chatDeleteToken
        $roleStr = if ($claims -and $claims.roles) { ($claims.roles -join " ") } else { "<none>" }
        Write-Host "Chat-delete token = app-only | roles=[$roleStr]"
        if ($roleStr -notmatch "Chat\.ManageDeletion") {
            Write-Host "WARNING: app token does NOT contain Chat.ManageDeletion.* - deletes will 403. Add the APPLICATION permission Chat.ManageDeletion.All and grant admin consent."
        }

        foreach ($c in $allChats) {
            $label = if ($c.topic) { $c.topic } else { "$($c.chatType) chat" }
            try {
                Invoke-Graph -Method DELETE -Uri "https://graph.microsoft.com/v1.0/chats/$($c.id)" -Token $chatDeleteToken -RetryOn @(429,500,502,503,504) | Out-Null
                Write-Host "Deleted chat [$label] -> $($c.id)"
                $chatsDeleted++
                Start-Sleep -Seconds $chatDeleteDelaySeconds   # respect 1 delete/sec/tenant
            }
            catch {
                if ((Get-GraphStatus $_) -eq 404) {
                    Write-Host "Chat [$label] already gone (404)"
                    continue
                }
                $msg = Resolve-ErrorMessage $_
                Write-Host "CHAT DELETE FAILED [$label]: $msg"
                [void]$failures.Add("chat [$label] -> $msg")
            }
        }
    }


    # ============================================
    # CALENDAR CLEANUP - delete ALL events for each user
    # ============================================
    $eventsDeleted = 0

    function Remove-AllEvents {
        param([string]$OrganiserUpn)
        $localDeleted = 0

        $ids = New-Object System.Collections.Generic.List[string]
        $uri = "https://graph.microsoft.com/v1.0/users/$OrganiserUpn/events?`$select=id,subject,type&`$top=100"
        while ($uri) {
            $resp = Invoke-Graph -Method GET -Uri $uri
            foreach ($e in $resp.value) { [void]$ids.Add($e.id) }
            $uri = $resp.'@odata.nextLink'
        }

        Write-Host "$OrganiserUpn : $($ids.Count) event(s) to delete"
        foreach ($id in $ids) {
            try {
                # Deleting a seriesMaster removes the whole recurring series too.
                Invoke-Graph -Method DELETE -Uri "https://graph.microsoft.com/v1.0/users/$OrganiserUpn/events/$id" | Out-Null
                $localDeleted++
            }
            catch {
                if ((Get-GraphStatus $_) -eq 404) { continue }
                $msg = Resolve-ErrorMessage $_
                Write-Host "  EVENT DELETE FAILED ($id): $msg"
                [void]$failures.Add("event $id ($OrganiserUpn) -> $msg")
            }
        }
        return $localDeleted
    }

    if ($cleanupEvents) {
        foreach ($p in $allUserPrefixes) {
            try {
                $u = Resolve-DirectoryUser -Prefix $p -Upn "$p@$domain"
                if (-not $u) {
                    Write-Host "Skipping $p (no directory user found)"
                    continue
                }
                $upn = if ($u.userPrincipalName) { $u.userPrincipalName } else { "$p@$domain" }
                $eventsDeleted += Remove-AllEvents -OrganiserUpn $upn
            }
            catch {
                $msg = Resolve-ErrorMessage $_
                Write-Host "FAILED clearing calendar for $p : $msg"
                [void]$failures.Add("calendar $p -> $msg")
            }
        }
    }


    # ============================================
    # RESPONSE
    # ============================================
    $summary = "chats deleted: $chatsDeleted; events deleted: $eventsDeleted; failures: $($failures.Count)"
    Write-Host $summary

    if ($failures.Count -eq 0) {
        $response = @{
            Status        = "Succeeded"
            Message       = "Teams cleanup complete. $summary"
            Domain        = $domain
            ODLUser       = $odlUser
            ChatsDeleted  = $chatsDeleted
            EventsDeleted = $eventsDeleted
        } | ConvertTo-Json
    }
    else {
        $response = @{
            Status        = "Failed"
            Message       = $summary
            Domain        = $domain
            ODLUser       = $odlUser
            ChatsDeleted  = $chatsDeleted
            EventsDeleted = $eventsDeleted
            Failures      = ($failures -join " || ")
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
