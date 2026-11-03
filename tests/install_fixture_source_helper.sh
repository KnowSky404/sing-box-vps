#!/usr/bin/env bash

# Test-only adapter for historical function fixtures. Keep their explicit path
# substitutions while isolating every new storage/global/legacy boundary. Real
# layout behavior is tested without this adapter by storage_layout and Docker.
set -euo pipefail

fixture_source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
case "${1:---source}" in
  --source)
    sed \
      -e 's|^readonly SB_DATA_ROOT=.*|readonly SB_DATA_ROOT="$(dirname "${BASH_SOURCE[0]}")"|' \
      -e 's|^readonly SB_PROJECT_DIR=.*|readonly SB_PROJECT_DIR="/root/sing-box-vps"|' \
      -e 's|^readonly SINGBOX_BIN_PATH=.*|readonly SINGBOX_BIN_PATH="/usr/local/bin/sing-box"|' \
      -e 's|^readonly SBV_BIN_PATH=.*|readonly SBV_BIN_PATH="/usr/local/bin/sbv"|' \
      -e 's|^readonly SINGBOX_SERVICE_FILE=.*|readonly SINGBOX_SERVICE_FILE="/etc/systemd/system/sing-box.service"|' \
      -e 's|^readonly SB_MEDIA_CHECK_DIR=.*|readonly SB_MEDIA_CHECK_DIR="${SB_PROJECT_DIR}/media-check"|' \
      "${fixture_source_root}/install.sh"
    ;;
  --isolate)
    fixture_file=${2:?fixture file required}
    [[ -f "${fixture_file}" && ! -L "${fixture_file}" ]] || exit 2
    sed -i \
      -e 's|^readonly SB_PROJECT_DIR="/root/sing-box-vps"$|readonly SB_PROJECT_DIR="${SB_DATA_ROOT}/runtime"|' \
      -e 's|^readonly SINGBOX_BIN_PATH="/usr/local/bin/sing-box"$|readonly SINGBOX_BIN_PATH="${SB_DATA_ROOT}/bin/sing-box"|' \
      -e 's|^readonly SBV_BIN_PATH="/usr/local/bin/sbv"$|readonly SBV_BIN_PATH="${SB_DATA_ROOT}/bin/sbv"|' \
      -e 's|^readonly SINGBOX_SERVICE_FILE="/etc/systemd/system/sing-box.service"$|readonly SINGBOX_SERVICE_FILE="${SB_DATA_ROOT}/systemd/sing-box.service"|' \
      -e 's|^readonly SBV_LINK_PATH=.*|readonly SBV_LINK_PATH="${SB_DATA_ROOT}/links/sbv"|' \
      -e 's|^readonly SINGBOX_LINK_PATH=.*|readonly SINGBOX_LINK_PATH="${SB_DATA_ROOT}/links/sing-box"|' \
      -e 's|^readonly SINGBOX_SERVICE_LINK_PATH=.*|readonly SINGBOX_SERVICE_LINK_PATH="${SB_DATA_ROOT}/links/sing-box.service"|' \
      -e 's|^readonly SB_LEGACY_PROJECT_DIR=.*|readonly SB_LEGACY_PROJECT_DIR="${SB_DATA_ROOT}/legacy"|' \
      -e 's|^readonly SB_LEGACY_BACKUP_DIR=.*|readonly SB_LEGACY_BACKUP_DIR="${SB_DATA_ROOT}/legacy-backups"|' \
      "${fixture_file}"
    fixture_directory=$(cd "$(dirname "${fixture_file}")" && pwd -P)
    fixture_root_declaration=$(printf 'readonly SB_DATA_ROOT=%q' "${fixture_directory}")
    SBV_FIXTURE_ROOT_DECLARATION="${fixture_root_declaration}" perl -pi -e \
      's/^readonly SB_DATA_ROOT=.*/$ENV{SBV_FIXTURE_ROOT_DECLARATION}/' "${fixture_file}"
    mkdir -p "${fixture_directory}/links" "${fixture_directory}/logs" "${fixture_directory}/tmp"
    chmod 700 "${fixture_directory}/links" "${fixture_directory}/logs" "${fixture_directory}/tmp"
    ;;
  *) printf 'usage: %s [--source|--isolate FILE]\n' "$0" >&2; exit 2 ;;
esac
