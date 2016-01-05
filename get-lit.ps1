
$LUVI_VERSION = "2.5.2"
$LIT_VERSION = "3.0.0"

if (test-path env:LUVI_ARCH) {
  $LUVI_ARCH = $env:LUVI_ARCH
} else {
  if ([System.Environment]::Is64BitProcess) {
    $LUVI_ARCH = "Windows-amd64"
  } else {
    $LUVI_ARCH = "Windows-ia32"
  }
}
$LUVI_URL = "https://github.com/luvit/luvi/releases/download/v$LUVI_VERSION/luvi-regular-$LUVI_ARCH.exe"
$LIT_URL = "https://lit.luvit.io/packages/luvit/lit/v$LIT_VERSION.zip"

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
