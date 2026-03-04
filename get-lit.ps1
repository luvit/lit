Set-StrictMode -Version Latest

# Set up variables and their environment overrides
$LUVI_PREFIX = if ($env:LUVI_PREFIX) { $env:LUVI_PREFIX } else { $PWD }
$LUVI_ENGINE = if ($env:LUVI_ENGINE) { $env:LUVI_ENGINE } else { "luajit" }
$LUVI_VERSION = if ($env:LUVI_VERSION) { $env:LUVI_VERSION } else { "2.15.0" }
$LIT_VERSION = if ($env:LIT_VERSION) { $env:LIT_VERSION } else { "3.9.0" }
$LUVIT_VERSION = if ($env:LUVIT_VERSION) { $env:LUVIT_VERSION } else { "latest" }

# OS detection
if ($env:LUVI_OS) {
  $LUVI_OS = $env:LUVI_OS
}
else {
  if (Get-Variable IsWindows -ErrorAction SilentlyContinue) {
    # We are on PS >= 6
    if ($IsWindows) { $LUVI_OS = "Windows" }
    elseif ($IsLinux) { $LUVI_OS = "Linux" }
    elseif ($IsMacOS) { $LUVI_OS = "Darwin" }
    else { $LUVI_OS = "$(uname -s)" }
  } else {
    # We are on PS <= 5.1, only available on Windows
    $LUVI_OS = "Windows"
  }
}

# Architecture detection
if ($env:LUVI_ARCH) {
  $LUVI_ARCH = $env:LUVI_ARCH
}
else {
  $LUVI_ARCH = "amd64"
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
  Write-Host "[*] Cleaning up"
  if (Test-Path $lit_zip) { Remove-Item $lit_zip -Force }
  if (Test-Path $luvit_zip) { Remove-Item $luvit_zip -Force }
  exit $exit_code
}

function Download([string] $url, [string] $file) {
  Write-Host "[*] Downloading ${file} from ${url}"

  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  for ($i = 5; $i -gt 0; $i--) {
    try {
      Invoke-WebRequest -Uri "$url" -OutFile "$file" -UseDefaultCredentials -ErrorAction Stop
      return
    }
    catch {
      if ($null -ne $_.Exception.Response) {
        $status = [int]$_.Exception.Response.StatusCode
        Write-Host "[!] Failed to download ${url} to ${file} (HTTP ${status})"
      }
      else {
        Write-Host "[!] Failed to download ${url} to ${file} ($($_.Exception.Message))"
      }

      if ($i -ge 1) {
        Write-Host "[*] Retrying in 5 seconds ($(5 - $i + 1)/5)"
        Start-Sleep -Seconds 5
      }
    }
  }

  Write-Host "[!] Failed to download ${url} to ${file}"
  Cleanup 1
}

function VersionGTE([string] $a, [string] $b) {
  [version]$verA = $a -replace "v", ""
  [version]$verB = $b -replace "v", ""
  return $verA -ge $verB
}

# Allow selecting latest, but real versions need a v prefix
if ($LUVI_VERSION -ne "latest") { $LUVI_VERSION = "v${LUVI_VERSION}" }
if ($LIT_VERSION -ne "latest") { $LIT_VERSION = "v${LIT_VERSION}" }
if ($LUVIT_VERSION -ne "latest") { $LUVIT_VERSION = "v${LUVIT_VERSION}" }

if (${LUVI_VERSION} -eq "latest") {
  $luvi_url = "https://github.com/luvit/luvi/releases/latest/download/luvi-${LUVI_OS}-${LUVI_ARCH}-${LUVI_ENGINE}-regular${exe_suffix}"
}
elseif (VersionGTE $LUVI_VERSION "2.15.0") {
  $luvi_url = "https://github.com/luvit/luvi/releases/download/${LUVI_VERSION}/luvi-${LUVI_OS}-${LUVI_ARCH}-${LUVI_ENGINE}-regular${exe_suffix}"
}
else {
  $luvi_url = "https://github.com/luvit/luvi/releases/download/${LUVI_VERSION}/luvi-regular-${LUVI_OS}_${LUVI_ARCH}${exe_suffix}"
}
$lit_url = "https://lit.luvit.io/packages/luvit/lit/${LIT_VERSION}.zip"
$luvit_url = "https://lit.luvit.io/packages/luvit/luvit/${LUVIT_VERSION}.zip"

Write-Host "[+] Installing luvit, lit and luvi to ${LUVI_PREFIX}"

# Lit 3.9.0 and newer require luvi >= 2.15.0
if ((VersionGTE $LIT_VERSION "3.9.0") -and !(VersionGTE $LUVI_VERSION "2.15.0")) {
  Write-Host "[!] Incompatible luvi version, lit $LIT_VERSION requires luvi 2.15.0 or newer you are using $LUVI_VERSION"
  Cleanup 1
}

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
