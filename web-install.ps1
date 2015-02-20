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

$LIT_VERSION = "0.9.6"
$LUVI_VERSION = "0.7.0"

if ($env:TEMP -eq $null) {
  $env:TEMP = Join-Path $env:SystemDrive 'temp'
}
$luviTempDir = Join-Path $env:TEMP "luvi"
$tempDir = Join-Path $luviTempDir "lit"
if (![System.IO.Directory]::Exists($tempDir)) {[System.IO.Directory]::CreateDirectory($tempDir)}

# download the package
Write-Host "Download Luvi"
$luviUrl = "https://github.com/luvit/luvi/releases/download/v$LUVI_VERSION/luvi-static-Windows-amd64.exe"
Download-File $luviUrl "luvi.exe"

# lit package
$litPackage = "https://github.com/luvit/lit/archive/$LIT_VERSION.zip"
$litFile = "lit.zip"
Download-File $litPackage $litFile

# download 7zip
Write-Host "Download 7Zip commandline tool"
$7zaExe = Join-Path $tempDir '7za.exe'
Download-File 'https://chocolatey.org/7za.exe' "$7zaExe"

# Create Lit.exe
Start-Process "$7zaExe" -ArgumentList "x -o`"$tempDir`" -y `"$litFile`"" -Wait -NoNewWindow
$env:LUVI_APP="$tempDir\lit-$LIT_VERSION"
$env:LUVI_TARGET="lit.exe"
Start-Process "luvi.exe" -Wait -NoNewWindow
$env:LUVI_APP=""
$env:LUVI_TARGET=""
