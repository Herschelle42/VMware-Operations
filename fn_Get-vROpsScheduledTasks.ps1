function Get-vROpsScheduledTasks {
<#
.SYNOPSIS
  This gets all the scheduled reports from vROps.
.DESCRIPTION
  Using plink get all the scheduled reports that are currently set up in vROps 7.0
  and return them as a custom object.
.EXAMPLE
  Get-vROpsScheduledTasks -ComputerName vrops.corp.local -Credential (Get-Credential)
.NOTES
  Author: Clint Fritz
  Requires plink.exe and access to ssh to the vROps server
  It is performed by a Cassandra DB lookup.
  Only tested on vROps 7.0.

  On first run to an SSH will receive the following message:

    You can fix \ avoid this by using the PuTTy gui first and connecting to the server and accepting the certificate.


    plink.exe : The server's host key is not cached in the registry. You
    At line:1 char:13
    +   $result = &($plinkExePath) -ssh $ComputerName -l $UserName -pw $Pas ...
    +             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        + CategoryInfo          : NotSpecified: (The server's ho...e registry. You:String) [], RemoteException
        + FullyQualifiedErrorId : NativeCommandError
 
    have no guarantee that the server is the computer you
    think it is.
    The server's ssh-ed25519 key fingerprint is:
    ssh-ed25519 256 bc:c0:d3:2b:87:ee:5b:37:7d:9d:3b:83:39:95:fa:a6
    If you trust this host, enter "y" to add the key to
    PuTTY's cache and carry on connecting.
    If you want to carry on connecting just once, without
    adding the key to the cache, enter "n".
    If you do not trust this host, press Return to abandon the
    connection.
    Store key in cache? (y/n)

#>
[CmdletBinding()]
Param (
    [Parameter(Mandatory)]
    [Alias("Server","IPAddress","FQDN")]
    [string]$ComputerName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory=$false)]
    [string]$plinkEXEPath = "C:\Program Files\Putty\plink.exe"
)

Begin {
$tempCmdFile = [System.Io.Path]::GetTempFileName()
$Username = $credential.username
$Password = $credential.getnetworkcredential().Password

if (-not (Test-Path -Path $plinkexepath -ErrorAction SilentlyContinue)) {
    throw "plink.exe not found at: $($plinkExePath)"
}

}
Process {

[array]$columns = "namespace","classtype","key","blobvalue","nce_content_report_schedule_reportschedule____metadata___definitionid","nce_content_report_schedule_reportschedule____metadata___nextscheduledruntime","nce_content_report_schedule_reportschedule____metadata___resourceid","strvalue","valuetype","version"
$Command = @"
`$VMWARE_PYTHON_BIN `$ALIVE_BASE/cassandra/apache-cassandra-3.9/bin/cqlsh.py --ssl --cqlshrc `$ALIVE_BASE/user/conf/cassandra/cqlshrc -e "select $($columns -join ",") from globalpersistence.nce_content_report_schedule_reportschedule;"
"@


foreach ($item in $Command) {
    Write-Verbose "[INFO] Command: $($item)"
}
$command | Out-File -FilePath $tempCmdFile -Encoding ascii
$result = &($plinkExePath) -ssh $ComputerName -l $UserName -pw $Password -m $tempCmdFile
foreach ($item in $result) {
    Write-Verbose "[INFO] Result: $($item)"
}

$params = @{
    Delimiter = '\|' 
    PropertyNames = $columns
}

#Create a temporary object, excluding the the header row.
[array]$tempObject = $result | ? { $_ -notmatch "\([0-9]* row[s]?\)" } | ConvertFrom-String @params | ? { $_.$($columns[0]).trim() -ne "$($columns[0])" }
    
#create a new object after trimming the values
$newObject = $tempObject.ForEach({
    $hash = [ordered]@{}
    $_.PSObject.Properties.ForEach({
        $hash.$($_.name) = "$($_.value)".trim()
    })
    $object = New-Object PSObject -Property $hash
    $object
})
$newObject

} 

End {}

}
