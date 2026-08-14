## BEGIN: PLATFORM INSERT START
param($Request, $TriggerMetadata)
try
{
$sysAddedUsername = $Request.Body.sysAddedUsername
$sysAddedPassword = $Request.Body.sysAddedPassword | ConvertTo-SecureString -asPlainText -Force
$sysAddedSubscriptionId = $Request.Body.sysAddedSubscriptionId
$sysAddedTenantId = $Request.Body.sysAddedTenantId
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $sysAddedUsername, $sysAddedPassword
Connect-AzAccount -ServicePrincipal -Credential $Credential -Tenant $sysAddedTenantId
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
    # INITIAL DELAY BEFORE MAIN EXECUTION
    # --------------------------------------------
    Write-Host "Waiting before starting main execution..."
    Start-Sleep -Seconds 10
    Write-Host "Wait complete. Starting main execution."


    # --------------------------------------------
    # AUTHENTICATION WITH RETRY (Graph app-only token)
    # --------------------------------------------
    $clientId     = $Request.Body.sysAddedUsername
    $clientSecret = $Request.Body.sysAddedPassword
    $tenantId     = $Request.Body.sysAddedTenantId

    $tokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"

    $body = @{
        client_id     = $clientId
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $clientSecret
        grant_type    = "client_credentials"
    }

    $maxTokenRetry = 5
    $tokenAttempt  = 0
    $accessToken   = $null

    while (-not $accessToken -and $tokenAttempt -lt $maxTokenRetry) {
        try {
            $tokenAttempt++
            Write-Host "Generating Graph token - Attempt $tokenAttempt"

            $tokenResponse = Invoke-RestMethod `
                -Method POST `
                -Uri $tokenUrl `
                -Body $body `
                -ContentType "application/x-www-form-urlencoded"

            $accessToken = $tokenResponse.access_token
            Write-Host "Graph Token Generated"
        }
        catch {
            Write-Host "Token attempt failed: $($_.Exception.Message)"
            if ($tokenAttempt -lt $maxTokenRetry) {
                Write-Host "Retrying token generation in 15 seconds..."
                Start-Sleep -Seconds 15
            }
            else {
                throw "Unable to generate Graph token after $maxTokenRetry attempts"
            }
        }
    }


    # --------------------------------------------
    # TENANT DOMAIN + USER SETUP
    # --------------------------------------------
    #
    # The tenant domain is taken from the ODL user ONLY. Whatever address is
    # passed in azureuser (e.g. odl_user_2349640@<domain> OR Megan_Bowen@<domain>),
    # we split on "@" and reuse the domain for every mailbox below.
    #
    # Megan is treated as the ODL / primary user, so she is built from the same
    # domain. Nothing about the tenant is hardcoded.

    $odlUser = $Request.Body.azureuser
    if ([string]::IsNullOrWhiteSpace($odlUser) -or ($odlUser -notmatch "@")) {
        throw "azureuser is missing or not a valid email; cannot resolve tenant domain."
    }

    $domain = ($odlUser.Split("@")[1]).Trim()
    Write-Host "Tenant domain resolved from ODL user: $domain"

    # Mailboxes in the lab. Full address = "<LocalPart>@$domain", EXCEPT Megan.
    # There is no separate Megan_Bowen mailbox: Megan IS the ODL user, so she maps
    # straight to the ODL address passed in azureuser.
    $U = @{
        Megan   = $odlUser
        Isaiah  = "Isaiah_Langer@$domain"
        Alex    = "Alex_Wilbur@$domain"
        Nestor  = "Nestor_Wilke@$domain"
        Joni    = "Joni_Sherman@$domain"
        Allan   = "Allan_Deyoung@$domain"
        Diego   = "Diego_Siciliani@$domain"
        Patti   = "Patti_Fernandez@$domain"
    }

    Write-Host "Primary (ODL) mailbox: $($U.Megan)"


    # --------------------------------------------
    # EMAIL DATASET (from AB-6008 seeding reference)
    # --------------------------------------------
    #
    # Each item: From / To / Subject / Offset (R-x day offset from run day) / Body.
    #
    # NOTE ON DATES: Graph sendMail stamps the message with the CURRENT time and
    # gives no way to backdate a genuinely-transported email. The Offset value is
    # kept for reference and used to send oldest-first so ordering is consistent.
    # If real R-x timestamps are required, a folder-injection method is needed
    # (which produces drafts, not received mail).

    $messages = @(

    # ===== MEGAN — RECEIVED (10) =====

    @{ From=$U.Nestor; To=$U.Megan; Offset=2; Subject="Your weekly PIM digest for Contoso"; Body=@"
Hi Megan,

Here is your weekly Privileged Identity Management (PIM) digest for the Contoso tenant.

- 3 eligible role activations this week
- 1 role assignment pending review
- No high-risk activations detected

No action required unless you want to review the pending assignment.

Regards,
IT Notifications (on behalf of Nestor Wilke)
"@ }

    @{ From=$U.Nestor; To=$U.Megan; Offset=3; Subject="Passkeys by default and retirement of Microsoft-provided SMS and voice authentication"; Body=@"
Hi Megan,

Microsoft is enabling passkeys by default and retiring Microsoft-provided SMS and voice authentication methods.

What this means:
- Passkeys become a default sign-in option
- SMS and voice OTP will be phased out over time
- Review your authentication methods policy before the change

Shared for your awareness.

Regards,
IT Notifications (on behalf of Nestor Wilke)
"@ }

    @{ From=$U.Nestor; To=$U.Megan; Offset=1; Subject="Microsoft Entra ID Protection Weekly Digest"; Body=@"
Hi Megan,

Your Microsoft Entra ID Protection weekly digest is ready.

- 0 users flagged as high risk
- 2 risky sign-ins auto-remediated
- 1 risk detection dismissed

No action needed this week.

Regards,
IT Notifications (on behalf of Nestor Wilke)
"@ }

    @{ From=$U.Patti; To=$U.Megan; Offset=1; Subject="Need your sign-off: Beacon customer hold comms"; Body=@"
Hi Megan,

The customer hold communication for Project Beacon is drafted and ready. I need your sign-off before we send it to affected accounts.

Could you review and approve today? Customer timelines depend on it.

Thanks,
Patti Fernandez
"@ }

    @{ From=$U.Isaiah; To=$U.Megan; Offset=2; Subject="Vendor shortlist - decision needed on evaluation criteria"; Body=@"
Hi Megan,

We've narrowed the vendor shortlist to three, but we need your decision on the evaluation criteria before we score them.

Specifically: how should we weight cost vs. integration effort vs. support SLA?

We're blocked until we hear from you.

Thanks,
Isaiah Langer
"@ }

    @{ From=$U.Nestor; To=$U.Megan; Offset=2; Subject="Can you approve the Summit agenda draft?"; Body=@"
Hi Megan,

The draft agenda for the Summit is ready for your approval. Once you sign off I'll lock the sessions and confirm speakers.

Can you approve the attached draft?

Regards,
Nestor Wilke
"@ }

    @{ From=$U.Allan; To=$U.Megan; Offset=1; Subject="Beacon remediation - sprint kicked off"; Body=@"
Hi Megan,

Just a heads-up that the Beacon remediation sprint kicked off this morning. The team is working through the priority fixes and I'll share progress at the end of the sprint.

No action needed from you.

Regards,
Allan Deyoung
"@ }

    @{ From=$U.Patti; To=$U.Megan; Offset=3; Subject="All-hands recap and recording now available"; Body=@"
Hi Megan,

Thanks to everyone who joined the all-hands. The recap and recording are now available on the team site.

Sharing for anyone who missed it - no action required.

Best,
Patti Fernandez
"@ }

    @{ From=$U.Diego; To=$U.Megan; Offset=3; Subject="Vendor contact list is out of date"; Body=@"
Hi Megan,

I noticed the vendor contact list is out of date - several contacts have left and a few numbers bounce. It should be refreshed and reassigned to an owner.

This might be something to delegate rather than handle yourself.

Thanks,
Diego Siciliani
"@ }

    @{ From=$U.Patti; To=$U.Megan; Offset=2; Subject="Who can own the onboarding doc refresh?"; Body=@"
Hi Megan,

The onboarding documentation needs a refresh before the next cohort starts. Who on the team can own this? Happy to help scope it, but it needs a clear owner.

Thanks,
Patti Fernandez
"@ }

    # ===== MEGAN — SENT (4) =====

    @{ From=$U.Megan; To=$U.Allan; Offset=6; Subject="Decision: Beacon GA on hold"; Body=@"
Hi Allan,

Confirming the decision: Beacon GA is on hold pending the remediation work. Please pause any launch-dependent tasks and keep the sprint focused on the priority fixes.

I'll revisit the GA date once we see sprint results.

Thanks,
Megan
"@ }

    @{ From=$U.Megan; To=$U.Patti; Offset=2; Subject="Portfolio status ahead of our 1:1"; Body=@"
Hi Patti,

Ahead of our 1:1, here's where the portfolio stands:
- Beacon: GA on hold, remediation in progress
- Summit: agenda in review
- Onboarding refresh: needs an owner

We can go deeper on any of these tomorrow.

Thanks,
Megan
"@ }

    @{ From=$U.Megan; To=$U.Nestor; Offset=3; Subject="Summit evidence pack - what I still need from you"; Body=@"
Hi Nestor,

For the Summit evidence pack I still need from you:
- Final agenda draft (approved)
- Confirmed speaker list
- Security/PIM summary for the compliance slide

Can you get these to me by end of week?

Thanks,
Megan
"@ }

    @{ From=$U.Megan; To=$U.Diego; Offset=1; Subject="Q3 actuals for the Summit pack - gentle chase"; Body=@"
Hi Diego,

Gentle chase - I still need the Q3 actuals for the Summit pack. Could you send them over when you get a chance? I'd like to finalize the numbers this week.

Thanks,
Megan
"@ }

    # ===== JONI — RECEIVED (8), incl. 2 recaps from Megan =====

    @{ From=$U.Megan; To=$U.Joni; Offset=13; Subject="Weekly Project Sync - recap & actions (25 Jul)"; Body=@"
Hi Joni,

Recap and actions from this week's Project Sync:
- Helios: rollout approach under discussion
- Griffin: budget revision in progress
- Nimbus: vendor credential issue flagged

Actions: owners to confirm next steps before the next sync.

Thanks,
Megan
"@ }

    @{ From=$U.Megan; To=$U.Joni; Offset=6; Subject="Weekly Project Sync - recap & actions (1 Aug)"; Body=@"
Hi Joni,

Recap and actions from today's Project Sync:
- Helios: moving to phased rollout (decided)
- Griffin: final budget circulated
- Nimbus: still blocked on vendor credentials

Actions logged - please follow up on the open items.

Thanks,
Megan
"@ }

    @{ From=$U.Allan; To=$U.Joni; Offset=10; Subject="DECIDED: Helios moves to phased rollout"; Body=@"
Hi Joni,

Decision made: Helios moves to a phased rollout rather than a single cutover. This lowers risk and lets us validate each phase.

Moving this thread to the decision log.

Regards,
Allan Deyoung
"@ }

    @{ From=$U.Diego; To=$U.Joni; Offset=7; Subject="Griffin budget revision - final version attached"; Body=@"
Hi Joni,

The Griffin budget revision is finalized - final version attached. All the earlier comments are incorporated.

Consider this thread closed unless you spot anything.

Thanks,
Diego Siciliani
"@ }

    @{ From=$U.Isaiah; To=$U.Joni; Offset=4; Subject="Nimbus still blocked - vendor credentials"; Body=@"
Hi Joni,

Nimbus is still blocked - we don't have the vendor credentials and the vendor hasn't responded. This is now a red item and is holding up the next milestone.

We need help escalating.

Thanks,
Isaiah Langer
"@ }

    @{ From=$U.Allan; To=$U.Joni; Offset=3; Subject="Joni - need your call on the Helios test window"; Body=@"
Hi Joni,

I need your call on the Helios test window - do we run it this weekend or push to next week? Each option has trade-offs for the phased rollout.

Can you let me know? I'm blocked until you decide.

Regards,
Allan Deyoung
"@ }

    @{ From=$U.Diego; To=$U.Joni; Offset=2; Subject="Can you confirm the Griffin steering invite list?"; Body=@"
Hi Joni,

Can you confirm the invite list for the Griffin steering meeting? I want to send invites today but need you to confirm who should attend.

Thanks,
Diego Siciliani
"@ }

    @{ From=$U.Nestor; To=$U.Joni; Offset=5; Subject="Fortnightly dashboard refresh - first run done"; Body=@"
Hi Joni,

The fortnightly dashboard refresh completed its first run successfully. Data is current as of today and the automation will run every two weeks from now.

No action needed - sharing for visibility.

Regards,
Nestor Wilke
"@ }

    # ===== ALEX — RECEIVED (3) =====

    @{ From=$U.Diego; To=$U.Alex; Offset=2; Subject="Atlas W8 numbers - strongest week yet"; Body=@"
Hi Alex,

Atlas week 8 numbers are in and it's the strongest week yet:
- Signups up 22% week-on-week
- Activation rate 47%
- Revenue up 19%

Figures match the metrics workbook. Great momentum.

Thanks,
Diego Siciliani
"@ }

    @{ From=$U.Patti; To=$U.Alex; Offset=2; Subject="Atlas - stakeholder update request"; Body=@"
Hi Alex,

Could you put together a short stakeholder update on Atlas? Leadership wants the latest W8 numbers and a one-line outlook.

Aiming to circulate it this week if possible.

Thanks,
Patti Fernandez
"@ }

    @{ From=$U.Allan; To=$U.Alex; Offset=4; Subject="Re: Atlas go/no-go on Education pricing"; Body=@"
Hi Alex,

Following up on the Atlas go/no-go for Education pricing - the decision was GO, with the discounted tier capped at the levels we discussed.

Logging this so we have the decision on record.

Regards,
Allan Deyoung
"@ }

    )

    # Send oldest-first (largest offset first) so relative order is consistent.
    $messages = $messages | Sort-Object -Property @{ Expression = { [int]$_.Offset }; Descending = $true }

    Write-Host "Loaded $($messages.Count) emails to seed."


    # --------------------------------------------
    # SEND FUNCTION (sends AS the From mailbox)
    # --------------------------------------------
    function Send-Mail {
        param($From, $To, $Subject, $Body)

        $emailPayload = @{
            message = @{
                subject = $Subject
                body = @{
                    contentType = "Text"
                    content     = $Body
                }
                toRecipients = @(
                    @{ emailAddress = @{ address = $To } }
                )
            }
            saveToSentItems = "true"
        } | ConvertTo-Json -Depth 6

        $maxRetries = 5
        $attempt    = 0
        $success    = $false

        while (-not $success -and $attempt -lt $maxRetries) {
            try {
                $attempt++
                Write-Host "Sending (attempt $attempt): FROM $From TO $To | $Subject"

                Invoke-RestMethod `
                    -Method POST `
                    -Uri "https://graph.microsoft.com/v1.0/users/$From/sendMail" `
                    -Headers @{ Authorization = "Bearer $accessToken" } `
                    -Body $emailPayload `
                    -ContentType "application/json"

                $success = $true
                Write-Host "  -> Sent"
            }
            catch {
                Write-Host "  -> Send failed: $($_.Exception.Message)"
                if ($attempt -lt $maxRetries) {
                    Write-Host "  -> Retrying in 20 seconds..."
                    Start-Sleep -Seconds 20
                }
                else {
                    throw "Mail failed after $maxRetries attempts (FROM $From TO $To | $Subject)"
                }
            }
        }
    }


    # --------------------------------------------
    # SEND ALL
    # --------------------------------------------
    function Send-AllMessages {
        foreach ($m in $messages) {
            Send-Mail -From $m.From -To $m.To -Subject $m.Subject -Body $m.Body
            Start-Sleep -Seconds 4
        }
    }

    $expectedMailCount = $messages.Count   # 25 send operations
    $maxAttempts = 4
    $attempt     = 0
    $success     = $false

    while (-not $success -and $attempt -lt $maxAttempts) {
        try {
            $attempt++
            Write-Host "Seeding batch attempt $attempt"
            Send-AllMessages
            Write-Host "All $expectedMailCount emails sent successfully"
            $success = $true
        }
        catch {
            Write-Host "Attempt $attempt failed: $($_.Exception.Message)"
            if ($attempt -lt $maxAttempts) {
                Write-Host "Retrying entire batch in 2 minutes..."
                Start-Sleep -Seconds 120
            }
            else {
                throw "Seeding execution failed after $maxAttempts attempts"
            }
        }
    }


    # -----------------------------
    # Success Response
    # -----------------------------
    $response = @{
        Status  = "Succeeded"
        Message = "All $expectedMailCount emails seeded successfully"
        Domain  = $domain
        ODLUser = $odlUser
    } | ConvertTo-Json

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body       = $response
    })

}
catch {
    Write-Host "Function execution failed: $($_.Exception.Message)"
    $response = @{
        Status  = "Failed"
        Message = $_.Exception.Message
    } | ConvertTo-Json

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::BadRequest
        Body       = $response
    })
}
}
catch
{
    $e = $_.Exception
    $message = @{Status = "Failed"; Message = $e.Message; InvocationId = $TriggerMetadata.InvocationId} | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body = $message})
}
