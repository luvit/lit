#!/bin/sh
set -u # exit on unset variables.

LUVI_PREFIX=${LUVI_PREFIX:-${PWD}}

LUVI_OS=${LUVI_OS:-"$(uname -s)"}
LUVI_ARCH=${LUVI_ARCH:-"$(uname -m)"}
LUVI_ENGINE=${LUVI_ENGINE:-luajit}

LUVI_VERSION=${LUVI_VERSION:-2.15.0}
LIT_VERSION=${LIT_VERSION:-3.8.5}
LUVIT_VERSION=${LUVIT_VERSION:-latest}

_lit_zip="${LUVI_PREFIX}/lit.zip"
_luvit_zip="${LUVI_PREFIX}/luvit.zip"
_luvi_bin="${LUVI_PREFIX}/luvi"
_lit_bin="${LUVI_PREFIX}/lit"
_luvit_bin="${LUVI_PREFIX}/luvit"

cleanup() {
    _exit=$1

    echo "[*] Cleaning up"
    rm -f "${_lit_zip}"
    rm -f "${_luvit_zip}"
    exit "${_exit}"
}

# download a file from $1 and save it as $2
download() {
    _url=$1
    _file=$2

    echo "[*] Downloading ${_file} from ${_url}"

    # --retry requires curl 7.12.3, from 2004
    _status="$(curl --retry 5 --retry-delay 5 -#Lfo "${_file}" -w "%{http_code}" "${_url}")"
    _exit="$?"
    if [ "${_exit}" -eq 2 ]; then # curl failed to start, probably not installed or version too old
        echo "[!] Failed to download ${_file} (curl initialization failed)"
        exit 1
    elif [ "${_exit}" -ne 0 ]; then # curl failed to download
        echo "[!] Failed to download ${_file} (curl exit ${_exit})"
        echo "curl: ${_status}"
        exit 1
    fi

    if [ "${_status}" -ne 200 ]; then # the server did not give us the file
        echo "[!] Failed to download ${_file} (HTTP ${_status})"
        exit 1
    fi
}

# check if version $1 is greater than or equal to $2
version_gte() {
    [ "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1" ] || [ "$1" = "$2" ]
}

# allow selecting latest, but real versions need a v prefix
[ "${LUVI_VERSION}" != "latest" ] && LUVI_VERSION="v${LUVI_VERSION}"
[ "${LIT_VERSION}" != "latest" ] && LIT_VERSION="v${LIT_VERSION}"
[ "${LUVIT_VERSION}" != "latest" ] && LUVIT_VERSION="v${LUVIT_VERSION}"

_luvi_url="https://github.com/luvit/luvi/releases/download/${LUVI_VERSION}/luvi-regular-${LUVI_OS}_${LUVI_ARCH}"
_lit_url="https://lit.luvit.io/packages/luvit/lit/${LIT_VERSION}.zip"
_luvit_url="https://lit.luvit.io/packages/luvit/luvit/${LUVIT_VERSION}.zip"

if [ "${LUVI_VERSION}" = "latest" ] || version_gte "${LUVI_VERSION}" "2.15.0"; then # select the new release format
    _luvi_url="https://github.com/luvit/luvi/releases/download/${LUVI_VERSION}/luvi-${LUVI_OS}-${LUVI_ARCH}-${LUVI_ENGINE}-regular"
fi

echo "[+] Installing luvit, lit and luvi to ${LUVI_PREFIX}"
trap 'echo "[#] Cancelling installation"; cleanup 1' INT TERM

# Download Luvi, and the sources for Lit and Luvit

download "${_luvi_url}" "${_luvi_bin}" || cleanup 1
download "${_lit_url}" "${_lit_zip}" || cleanup 1
download "${_luvit_url}" "${_luvit_zip}" || cleanup 1

# Install luvi

chmod +x "${_luvi_bin}"
if [ ! -x "${_luvi_bin}" ]; then
    echo "[!] Could not make luvi executable"
    cleanup 1
fi

# Install lit

echo "[*] Creating lit from lit.zip"
"${_luvi_bin}" "${_lit_zip}" -- make "${_lit_zip}" "${_lit_bin}" "${_luvi_bin}"
if [ ! -x "${_lit_bin}" ]; then
    echo "[!] Could not create lit"
    cleanup 1
fi

# Install luvit

echo "[*] Creating luvit from luvit.zip"
"${_lit_bin}" make "${_luvit_zip}" "${_luvit_bin}" "${_luvi_bin}"
if [ ! -x "${_luvit_bin}" ]; then
    echo "[!] Could not create luvit"
    cleanup 1
fi

echo "[+] Installation complete at ${LUVI_PREFIX}"

cleanup 0
