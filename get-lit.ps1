
$LUVI_VERSION = "2.0.5"
$LIT_VERSION = "1.2.0"

$LUVI_ARCH = "Windows-amd64"
$LUVI_URL = "https://github.com/luvit/luvi/releases/download/v$LUVI_VERSION/luvi-regular-$LUVI_ARCH.exe"
$LIT_URL = "https://github.com/luvit/lit/archive/$LIT_VERSION.zip"

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

# Download Files
Download-File $LUVI_URL "luvi.exe"
Download-File $LIT_URL "lit.zip"

# Create lit.exe using lit
Start-Process "luvi.exe" -ArgumentList "lit.zip -- make lit.zip" -Wait -NoNewWindow

# Cleanup
Remove-Item "lit.zip"
