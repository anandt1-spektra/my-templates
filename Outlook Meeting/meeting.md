# Details 

Single User hai, with license and extra user nhii hai and uske outlook pr hume ek meeting chaiye with the below details uske liye ye Deployment script hai 

  ```
  Project Planning Workshop 
  today, 
  8:00 AM–12:00 PM UTC
  ```


  ```powershell
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
  
  $ErrorActionPreference = "Stop"
  $today = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
  
  # Token for the ODL user
  $token = (Invoke-RestMethod -Method Post `
      -Uri "https://login.microsoftonline.com/$sysAddedTenantId/oauth2/v2.0/token" `
      -ContentType "application/x-www-form-urlencoded" `
      -Body @{
          client_id  = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
          scope      = "https://graph.microsoft.com/Calendars.ReadWrite offline_access openid profile"
          username   = $azureuseremail
          password   = $azureuserpassword
          grant_type = "password"
      }).access_token
  
  $headers = @{ Authorization = "Bearer $token" }
  
  # Remove any copy left by an earlier run
  $dupes = (Invoke-RestMethod -Method Get -Headers $headers `
      -Uri ("https://graph.microsoft.com/v1.0/me/calendarView?startDateTime={0}T00:00:00Z&endDateTime={0}T23:59:59Z&`$select=id,subject&`$top=100" -f $today)).value |
      Where-Object { $_.subject -eq "Project Planning Workshop" }
  
  foreach ($d in $dupes) {
      Invoke-RestMethod -Method Delete -Headers $headers `
          -Uri "https://graph.microsoft.com/v1.0/me/events/$($d.id)" | Out-Null
  }
  
  # Create the meeting
  Invoke-RestMethod -Method Post -Headers $headers `
      -Uri "https://graph.microsoft.com/v1.0/me/events" `
      -ContentType "application/json" `
      -Body (@{
          subject = "Project Planning Workshop"
          body    = @{ contentType = "HTML"; content = "Project Planning Workshop session." }
          start   = @{ dateTime = "$($today)T08:00:00.0000000"; timeZone = "UTC" }
          end     = @{ dateTime = "$($today)T12:00:00.0000000"; timeZone = "UTC" }
      } | ConvertTo-Json -Depth 5) | Out-Null
  
  Write-Host "Meeting created for $azureuseremail on $today 08:00-12:00 UTC."
  }
  catch
  {
      $e = $_.Exception
      $message = @{Status ="Failed"; Message = $e.Message}| ConvertTo-Json
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                                StatusCode = [System.Net.HttpStatusCode]::OK
                                Body = $message})
  }
  ```
