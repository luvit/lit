
$LIT_VERSION = "0.9.7"
$LUVI_VERSION = "0.7.0"

function Download-File {
param (
  [string]$url,
  [string]$file
 )
  Write-Host "Downloading $url to $file"
  $downloader = new-object System.Net.WebClient
  $downloader.Proxy.Credentials=[System.Net.CredentialCache]::DefaultNetworkCredentials;
  $downloader.DownloadFile($url, $file)
}

# download the package
Write-Host "Download Luvi"
$luviUrl = "https://github.com/luvit/luvi/releases/download/v$LUVI_VERSION/luvi-static-Windows-amd64.exe"
Download-File $luviUrl "luvi.exe"

# lit package
$litPackage = "https://github.com/luvit/lit/archive/$LIT_VERSION.zip"
$litFile = "lit.zip"
Download-File $litPackage $litFile

# Create Lit.exe
$env:LUVI_APP="$litFile"
Start-Process "luvi.exe" -ArgumentList "make $litFile" -Wait -NoNewWindow
$env:LUVI_APP=""
