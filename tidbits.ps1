
# vROps server details
$vropsServer = "operations.corp.local"
$username = "username"
$password = "password"
<#
Valid values?
LOCAL
SYSTEM DOMAIN
vIDMAuthSource  if connected to vIDM
<AD Domain name> as configured in Authenticateion Sources (v8.18)
#>
$authSource = 'corp.local'

# Authentication endpoint
$authEndpoint = "https://$($vropsServer)/suite-api/api/auth/token/acquire"

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

$headers.Add("Authorization", "vRealizeOpsToken $($authResponse.token)")
#copy to clipboard for use in the Swagger ui
$authResponse.token | Set-Clipboard
