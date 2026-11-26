param([Parameter(Mandatory=$true)][uri]$Uri,
      [Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
if($Uri.Scheme -ne 'https'){throw 'Only HTTPS research assets are supported.'}
Invoke-WebRequest -Uri $Uri -OutFile $Destination -TimeoutSec 120 -UseBasicParsing
