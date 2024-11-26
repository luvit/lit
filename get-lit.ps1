Set-StrictMode -Version Latest

$LUVI_PREFIX = $PWD

$LUVI_OS = "Windows"
$LUVI_ARCH = "amd64"
$LUVI_ENGINE = "luajit"

$LUVI_VERSION = "2.15.0"
$LIT_VERSION = "3.8.5"
$LUVIT_VERSION = "latest"

# Check for environment variable overrides
if ($null -ne $env:LUVI_PREFIX) { $LUVI_PREFIX = $env:LUVI_PREFIX }
if ($null -ne $env:LUVI_OS) { $LUVI_OS = $env:LUVI_OS }
if ($null -ne $env:LUVI_ARCH) { $LUVI_ARCH = $env:LUVI_ARCH }
if ($null -ne $env:LUVI_ENGINE) { $LUVI_ENGINE = $env:LUVI_ENGINE }
if ($null -ne $env:LUVI_VERSION) { $LUVI_VERSION = $env:LUVI_VERSION }
if ($null -ne $env:LIT_VERSION) { $LIT_VERSION = $env:LIT_VERSION }
if ($null -ne $env:LUVIT_VERSION) { $LUVIT_VERSION = $env:LUVIT_VERSION }

if ($null -eq $env:LUVI_OS) {
  # OS detection
  if (-not (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue) -or $IsWindows) {
    $LUVI_OS = "Windows"
  }
  elseif ($IsLinux) {
    $LUVI_OS = "Linux"
  }
  elseif ($IsMacOS) {
    $LUVI_OS = "Darwin"
  }
  else {
    $LUVI_OS = "$(uname -s)"
  }
}

if ($null -eq $env:LUVI_OS) {
  # Architecture detection
  if ($null -ne $env:PROCESSOR_ARCHITEW6432) {
    $LUVI_ARCH = ($env:PROCESSOR_ARCHITEW6432).ToLower()
  }
  elseif ($null -ne $env:PROCESSOR_ARCHITECTURE) {
    $LUVI_ARCH = ($env:PROCESSOR_ARCHITECTURE).ToLower()
  }
  else {
    $LUVI_ARCH = "$(uname -m)"
  }
}

$exe_suffix = ""
if ($LUVI_OS -eq "Windows") { $exe_suffix = ".exe" }

$lit_zip = Join-Path "${LUVI_PREFIX}" "lit.zip"
$luvit_zip = Join-Path "${LUVI_PREFIX}" "luvit.zip"
$luvi_bin = Join-Path "${LUVI_PREFIX}" "luvi${exe_suffix}"
$lit_bin = Join-Path "${LUVI_PREFIX}" "lit${exe_suffix}"
$luvit_bin = Join-Path "${LUVI_PREFIX}" "luvit${exe_suffix}"

function Cleanup([int] $exit_code) {
  if (Test-Path $lit_zip) { Remove-Item $lit_zip -Force }
  if (Test-Path $luvit_zip) { Remove-Item $luvit_zip -Force }
  exit $exit_code
}

function Download([string] $url, [string] $file) {
  Write-Host "[*] Downloading ${file} from ${url}"

  [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
  $client = New-Object System.Net.WebClient
  $client.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
  for ($i = 5; $i -ge 0; $i--) {
    try {
      $client.DownloadFile($url, $file)
      return
    }
    catch [Net.WebException] {
      if ($null -ne $_.Exception.Response) {
        $status = [int]$_.Exception.Response.StatusCode

        Write-Host "[!] Failed to download ${url} to ${file} (HTTP ${status})"
      }
      else {
        Write-Host "[!] Failed to download ${url} to ${file} ($($_.Exception.Message))"
      }

      if ($i -gt 0) {
        Write-Host "[*] Retrying in 5 seconds"
        Start-Sleep 5
      }
    }
  }

  Write-Host "[!] Failed to download ${url} to ${file}"
  Cleanup 1
}

function VersionGTE([string] $a, [string] $b) {
  $a = $a -split '\.'
  $b = $b -split '\.'
  for ($i = 0; $i -lt $a.Length; $i++) {
    if ($i -ge $b.Length) { return $true }
    if ($a[$i] -gt $b[$i]) { return $true }
    if ($a[$i] -lt $b[$i]) { return $false }
  }
  return $true
}

if ($LUVI_VERSION -ne "latest") { $LUVI_VERSION = "v${LUVI_VERSION}" }
if ($LIT_VERSION -ne "latest") { $LIT_VERSION = "v${LIT_VERSION}" }
if ($LUVIT_VERSION -ne "latest") { $LUVIT_VERSION = "v${LUVIT_VERSION}" }

$luvi_url = "https://github.com/luvit/luvi/releases/download/${LUVI_VERSION}/luvi-regular-${LUVI_OS}_${LUVI_ARCH}${exe_suffix}"
$lit_url = "https://lit.luvit.io/packages/luvit/lit/${LIT_VERSION}.zip"
$luvit_url = "https://lit.luvit.io/packages/luvit/luvit/${LUVIT_VERSION}.zip"

if (${LUVI_VERSION} -eq "latest" -or (VersionGTE $LUVI_VERSION "2.15.0")) {
  $luvi_url = "https://github.com/luvit/luvi/releases/download/${LUVI_VERSION}/luvi-${LUVI_OS}-${LUVI_ARCH}-${LUVI_ENGINE}-regular${exe_suffix}"
}

Write-Host "[+] Installing luvit, lit and luvi to ${LUVI_PREFIX}"

# Download Luvi, and the sources for Lit and Luvit

Download $luvi_url $luvi_bin
Download $lit_url $lit_zip
Download $luvit_url $luvit_zip

# Install luvi

if ("${LUVI_OS}" -ne "Windows") {
  &chmod +x $luvi_bin
}

# Install lit

Write-Host "[*] Creating lit from lit.zip"
&"${luvi_bin}" "${lit_zip}" -- make "${lit_zip}" "${lit_bin}" "${luvi_bin}"
if (-not (Test-Path $lit_bin)) {
  Write-Host "[!] Could not create lit"
  Cleanup 1
}

# Install Luvit

Write-Host "[*] Creating luvit from luvit.zip"
&"${lit_bin}" make "${luvit_zip}" "${luvit_bin}" "${luvi_bin}"
if (-not (Test-Path $luvit_bin)) {
  Write-Host "[!] Could not create luvit"
  Cleanup 1
}

Write-Host "[+] Installation complete at ${LUVI_PREFIX}"

Cleanup 0
