<#
.SYNOPSIS
  Get the machines that are currently scheduled for changes in Automation Central
.DESCRIPTION
  This script is report on which Machines are currently scheduled for upcoming 
  changes in Automation Central. This is to allow to report this information as
  there does not appear to be a display in the UI that makes this easy. This 
  script uses UNSUPPORTED internal API calls. There is no support for this 
  script by VMware or Broadcom Support.

  This script is just a quick and dirty and could do with many enhancements link
  adding parameters, validation and error checking.
.NOTES
  Only tested on Aria Operations 8.18.1

  machine name:           id -> then get the machine name
  operation:              actionDetails.scheduleOperation
  scheduled time:         scheduleConfig.startDate
  schedule name:          name
  schedule description:   description

  INPUTS
  username
  password

  $VerbosePreference = "Continue"
  $authResponse.token | Set-Clipboard

#>


#region --- Variables and Inputs ----------------------------------------------

$opsServer = "vrops.corp.local"
#Must be the Source Display Name from Control Panel -> Auth Sources
$authSource = "CORP AD"

$username = Read-Host -Prompt "Please enter username"
$SecureString = Read-Host -Prompt "Please enter password" -AsSecureString

#must be decrypted for use in authenticating to Operations
if ($PSVersionTable.PSVersion.Major -le 5) {
    #$password = ConvertFrom-SecureStringToPlainText -SecureString $SecureString
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)) 

} else {
    #PSv7
    $password = $passwordSecure | ConvertFrom-SecureString -AsPlainText
}

$ISODateTime = Get-Date -uFormat "%Y-%m-%d-%H-%M-%S"

$filePath = "$($env:USERPROFILE)\Documents\Operations Schedule of Machines $($ISODateTime).csv"

#endregion ---


#region --- Authentication ----------------------------------------------------

# Authentication endpoint
$authEndpoint = "https://$($opsServer)/suite-api/api/auth/token/acquire"

# Create base64-encoded credentials
$base64Credentials = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($username):$($password)"))

try {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
} catch {
    Write-Warning "Your organisation has broken stuff!"
    Write-Output "[ERROR] $(Get-Date) Exception: $($_.Exception)"
    throw
}
$headers.Add("Accept", 'application/json')
$headers.Add("Content-Type", 'application/json')

$authBody = @{
    username=$username
    password=$password
    authSource=$authSource
}
$body = $authBody | ConvertTo-Json

$authResponse = Invoke-RestMethod -Uri $authEndpoint -Method POST -Headers $headers -Body $body

# Check if authentication was successful
if ($authResponse.token -ne $null) {
    Write-Output "Authentication successful."
} else {
    Write-Output "ERROR: Authentication failed."
    Return
}
#Create 
#$headers.Add("Authorization", "vRealizeOpsToken $($authResponse.token)")
$headers.Add("Authorization", "OpsToken $($authResponse.token)")

#endregion


#region --- Get Schedule ------------------------------------------------------

#Required additional header data for this internal API
#If missing will receive:  Invoke-RestMethod : HTTP Status 403 – Forbiddenbody
if($headers.Keys | ? { $_ -match "unsupported" }) {
    #do nothing already added
} else {
    $headers.Add("X-Ops-API-use-unsupported", $true)
}

$method = "GET"
$uri = "https://$($opsServer)/suite-api/internal/actions/automation/schedules?_no_links=true"
try {
    $schedulesResponse = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers
} catch {
    throw
}

$scheduleList = $schedulesResponse.actionSchedules | Where-Object { $_.status -eq "ENABLED" }

if($scheduleList.count -lt 1) {
    Write-Warning "There are currently no scheduled Jobs or none that are Enabled."
    Return
}

#$scheduleList | Select Name, status

#endregion 


#region --- Get machine details -----------------------------------------------

$machineList = @()

$pageSize = 1000
$pageCount = 1
$startItem = 0

<#
Query returns 17,317 Virtual Machines so need to do some more tweaking of the query.

Q: is it picking up old deleted objects like backups?
A: yes appears so at the customer

#exclude names ending in BACKUP ^(?!.*BACKUP$).*
&regex=%5E(%3F!.*BACKUP%24).*

This alone reduces the results to 2,443

#with an added name regex to search
$uri = "https://$($opsServer)/suite-api/api/resources?adapterKind=VMware&page=0&pageSize=1000&regex=dev.*&resourceKind=VirtualMachine&_no_links=true"

#>
$method = "GET"
$uri = "https://$($opsServer)/suite-api/api/resources?adapterKind=VMWARE&page=$($pageCount-1)&pageSize=$($pageSize)&resourceKind=VirtualMachine&regex=%5E(%3F!.*BACKUP%24).*&_no_links=true"

try {
    $machineResponse = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers
} catch {
    Write-Output "Error Exception Type:   [$($_.exception.gettype().fullname)]"
    Write-Output "Error Message:          $($_.ErrorDetails.Message)"
    Write-Output "Exception Message:      $($_.Exception.Message)"
    Write-Output "StatusCode:             $($_.Exception.Response.StatusCode.value__)"
    throw
}
$list = $machineResponse.resourceList
$totalCount = $machineResponse.pageInfo.totalCount

if($totalCount -gt $pageSize) {
    $endItem = $pageSize-1
} else {
    $endItem = $totalCount
}
$pageTotal = [Math]::Ceiling($totalCount / $pageSize)


Write-Verbose "$(Get-Date) Total items to process: $($totalCount)"
Write-Verbose "$(Get-Date) Page Size: $($pageSize)"
Write-Verbose "$(Get-Date) Total Pages: $($pageTotal)"

Write-Verbose "$(Get-Date) Start Item: $($startItem)"
Write-Verbose "$(Get-Date) End Item: $($endItem)"


while ($pageCount -le $pageTotal) {
    Write-Verbose "$(Get-Date) Processing Page: $($pageCount) of $($pageTotal) - $($startItem)..$($endItem)"

    #Do processing here - $list[$startItem..$endItem]
    #add to array
    $machineList += $list
        
    #increment
    $pageCount++
    $startItem = $startItem + $pageSize
    $endItem = $endItem + $pageSize
    if($endItem -gt $totalCount) {
        $endItem = $totalCount-1
    }


    #Get the next page of data, first updating the uri
    $uri = "https://$($opsServer)/suite-api/api/resources?adapterKind=VMWARE&page=$($pageCount-1)&pageSize=$($pageSize)&resourceKind=VirtualMachine&regex=%5E(%3F!.*BACKUP%24).*&_no_links=true"

    try {
        $machineResponse = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers
    } catch {
        Write-Output "Error Exception Type:   [$($_.exception.gettype().fullname)]"
        Write-Output "Error Message:          $($_.ErrorDetails.Message)"
        Write-Output "Exception Message:      $($_.Exception.Message)"
        Write-Output "StatusCode:             $($_.Exception.Response.StatusCode.value__)"
        throw
    }
    $list = $machineResponse.resourceList

}


$selMachineName = @{Name='MachineName'; Expression={$_.resourceKey.name}}
#$machineList | Select $selMachineName, identifier | Sort MachineName
Write-Verbose "$(Get-Date) Machine Count: $($machineList.count)"


#endregion


#region --- Create report -----------------------------------------------------

$report = foreach($schedule in $scheduleList) {
    foreach($vmId in $schedule.actionScope.virtualMachineIds) {
        

        $hash = [ordered]@{}

        if($machine = $machineList | Where-Object { $_.identifier -eq $vmId }) {
            $hash.MachineName = $machine.resourceKey.name
        } else {
            $hash.MachineName = $null
        }
        $hash.Operations = $schedule.actionDetails.scheduleOperation
        $hash.Date = $schedule.scheduleConfig.startDate
        $hash.TimeZone = $schedule.scheduleConfig.timeZone
        $hash.ScheduleName = $schedule.name
        $object = New-Object PSObject -Property $hash
        $object

    }
}
$report | ft -AutoSize

$report | Export-Csv -Path $filePath -NoTypeInformation

#endregion -------------------------

