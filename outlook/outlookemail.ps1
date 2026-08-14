
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
## BEGIN: PLATFORM INSERT START

## BEGIN: VARIABLES SECTION INSERT START
$azureuser = $Request.Body.azureuser
## END: VARIABLES SECTION INSERT END

try {

# --------------------------------------------
# INITIAL DELAY BEFORE MAIN EXECUTION
# --------------------------------------------

Write-Host "Waiting 2 minutes before starting main execution..."
Start-Sleep -Seconds 10
Write-Host "Wait complete. Starting main execution."


# --------------------------------------------
# AUTHENTICATION WITH RETRY
# --------------------------------------------

$clientId = $Request.Body.sysAddedUsername
$clientSecret = $Request.Body.sysAddedPassword
$tenantId = $Request.Body.sysAddedTenantId

$tokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"

$body = @{
    client_id     = $clientId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $clientSecret
    grant_type    = "client_credentials"
}

$maxTokenRetry = 5
$tokenAttempt = 0
$accessToken = $null

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
# MAILBOX USED FOR DEMO
# --------------------------------------------

# $domain = ($azureuser.Split("@")[1])
$user= $Request.Body.azureuser


# --------------------------------------------
# EMAIL DATASET - ZAVA FESTIVE CAMPAIGN
# --------------------------------------------

$conversations=@(

@{
Subject="Urgent: Final Approval Needed for Zava Festive Campaign Creatives"

Emails=@(

@"
Hi Marketing Leadership,

The final creative set for the Zava Festive Campaign is ready for sign-off. We need approval by 3:00 PM today to meet media publishing timelines.

Assets included:

* Homepage banners
* Social media ads
* In-store posters
* Email campaign creatives

Please review urgently.

Regards,
Neha Kapoor
Brand Marketing
"@

)
},

@{
Subject="Vendor Confirmation Pending for Diwali Gift Hampers"

Emails=@(

@"
Hi Procurement Team,

We are still awaiting confirmation from two vendors for Diwali gift hamper packaging and ribbon supplies.

If not confirmed today, dispatch timelines may be impacted.

Please prioritize follow-up.

Thanks,
Amit Verma
Festive Sourcing Lead
"@

)
},

@{
Subject="Store Readiness Checklist for Festive Campaign Launch"

Emails=@(

@"
Hello Regional Managers,

Please ensure all stores complete the festive launch readiness checklist by Friday evening.

Checklist includes:

* Decorative installations completed
* Promotional signage placed
* Gift wrapping counters ready
* Staff briefed on offers

Share completion status by EOD.

Regards,
Retail Operations
"@

)
},

@{
Subject="Action Required: Festive Discount Codes Not Working on Website"

Emails=@(

@"
Hi E-commerce Support,

Customers are reporting that FESTIVE20 and DIWALI10 discount codes are failing during checkout.

Please investigate immediately as campaign traffic has started increasing.

Impact:

* Cart abandonment risk
* Negative customer sentiment
* Revenue loss

Regards,
Digital Commerce Team
"@

)
},

@{
Subject="Weekly Update: Zava Festive Campaign Media Performance"

Emails=@(

@"
Hi Team,

Please find this week's campaign performance snapshot:

* Social CTR up 18%
* Email open rate at 31%
* Website traffic up 24%
* Best performing category: Home Decor

Detailed dashboard attached.

Best,
Performance Marketing Team
"@

)
},

@{
Subject="Meeting Invite: Festive Campaign Daily War Room"

Emails=@(

@"
Hello Everyone,

You are invited to the daily Festive Campaign War Room starting tomorrow at 10:00 AM.

Agenda:

* Sales updates
* Inventory risks
* Marketing performance
* Customer escalations

Meeting link attached.

Regards,
Campaign PMO
"@

)
},

@{
Subject="Customer Feedback: Loved the Festive Store Experience"

Emails=@(

@"
Dear Zava Retail Team,

I visited your Indore store yesterday and loved the festive decorations and staff support. The gift wrapping service was excellent.

Please appreciate the store team.

Regards,
Sneha Joshi
"@

)
},

@{
Subject="Pending Content Needed for Festive Email Blast"

Emails=@(

@"
Hi Content Team,

We still need the final product copy and subject line options for tomorrow's festive email blast.

Deadline: Today, 6:00 PM

Please share urgently so CRM can schedule the campaign.

Thanks,
CRM Marketing
"@

)
},

@{
Subject="Inventory Alert: Diyas and Lights Running Low"

Emails=@(

@"
Hi Supply Chain Team,

Stocks of decorative diyas and LED string lights are running low across top-performing stores.

Requested action:

* Prioritize replenishment
* Shift stock from low-demand stores
* Share ETA

Regards,
Merchandising Operations
"@

)
},

@{
Subject="Research Request: Gather All Updates on Zava Festive Campaign"

Emails=@(

@"
Hi Team,

Can someone compile all recent discussions, emails, files, and campaign progress updates related to the Zava Festive Campaign?

We need:

* Current launch readiness status
* Risks/issues open
* Pending approvals
* Performance updates
* Next steps

Needed before leadership review tomorrow.

Regards,
Rahul Sethi
Chief Marketing Office
"@

)
}

)

Write-Host "Conversation templates loaded"


function Send-Mail {

param($Subject,$Body)

$emailPayload=@{
message=@{
subject=$Subject
body=@{
contentType="Text"
content=$Body
}
toRecipients=@(
@{
emailAddress=@{
address=$user
}
}
)
}
saveToSentItems="true"
} | ConvertTo-Json -Depth 6


$maxRetries = 5
$attempt = 0
$success = $false

while(-not $success -and $attempt -lt $maxRetries){

try{

$attempt++

Write-Host "Sending Mail Attempt $attempt : $Subject"

Invoke-RestMethod `
-Method POST `
-Uri "https://graph.microsoft.com/v1.0/users/$user/sendMail" `
-Headers @{Authorization="Bearer $accessToken"} `
-Body $emailPayload `
-ContentType "application/json"

$success = $true
Write-Host "Mail Sent Successfully"

}
catch{

Write-Host "Mail send failed: $($_.Exception.Message)"

if($attempt -lt $maxRetries){

Write-Host "Retrying in 20 seconds..."
Start-Sleep -Seconds 20

}
else{

throw "Mail failed after $maxRetries attempts"

}

}

}

}


# --------------------------------------------
# GENERATE THREADS
# --------------------------------------------

function Send-AllConversations {
foreach($conv in $conversations){

$subject=$conv.Subject

for($i=0;$i -lt $conv.Emails.Count;$i++){

$body=$conv.Emails[$i]

if($i -eq 0){
$mailSubject=$subject
}
else{
$mailSubject="RE: $subject"
}

Send-Mail $mailSubject $body

Write-Host "Mail Sent: $mailSubject"

Start-Sleep -Seconds 4

}

}
}

$expectedMailCount = 10
$maxAttempts = 4
$attempt = 0
$success = $false

while(-not $success -and $attempt -lt $maxAttempts){

try{

$attempt++

Write-Host "Conversation batch attempt $attempt"

Send-AllConversations

Write-Host "All conversation emails sent successfully"

$success = $true

}
catch{

Write-Host "Attempt $attempt failed: $($_.Exception.Message)"

if($attempt -lt $maxAttempts){

Write-Host "Retrying entire conversation batch in 2 minutes..."
Start-Sleep -Seconds 120

}
else{

throw "Conversation execution failed after $maxAttempts attempts"

}

}

}


# -----------------------------
# Success Response
# -----------------------------
$response = @{
    Status="Succeeded"
    Message="All conversation emails sent successfully"
    Mailbox=$user
} | ConvertTo-Json

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode=[System.Net.HttpStatusCode]::OK
    Body=$response
})

}
catch {

Write-Host "Function execution failed: $($_.Exception.Message)"

$response = @{
    Status="Failed"
    Message=$_.Exception.Message
} | ConvertTo-Json

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode=[System.Net.HttpStatusCode]::BadRequest
    Body=$response
})

}
}
catch
{
    $e = $_.Exception
    $message = @{Status ="Failed"; Message = $e.Message; InvocationId = $TriggerMetadata.InvocationId} | ConvertTo-Json
              Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                              StatusCode = [System.Net.HttpStatusCode]::OK
                              Body = $message})

}
