#!/bin/bash
# =========================================================
# Crave build script — AOSP Android 16 (r4) for Sony Tama (akari)
# with kernel 5.4 (built from source) + retrofit dynamic partitions.
#
# Usage (on Crave):   bash aosp.sh
# Optional: export TG_BOT_TOKEN and TG_CHAT_ID for Telegram progress.
# =========================================================

# ------------------------- CONFIG -------------------------
DEVICE=akari
LUNCH_TARGET=aosp_h8266-userdebug        # XZ2 Dual; use aosp_h8216 for XZ2
MANIFEST_URL=https://github.com/Tama-5-4-lineage/manifest
MANIFEST_BRANCH=main
BUILD_TARGET="AOSP"
ANDROID_VERSION="16"
export TZ="Asia/Jakarta"

TG_BOT_TOKEN="${TG_BOT_TOKEN:-$(echo "ODQ2NTAyMTE4MjpBQUc0YzdjejBOMktUbTBlcUxkc05kZVJZVUR3Q01GSVF1Zw==" | base64 -d)}"
TG_CHAT_ID="${TG_CHAT_ID:-$(echo "LTEwMDE5MzAxNjgyNjk=" | base64 -d)}"

START_TIME=$(date +%s)
OUT="out/target/product/$DEVICE"

# ------------------------- HELPERS ------------------------
log()  { echo -e "\n\033[1;36m>>> [$(date '+%H:%M:%S')] $*\033[0m"; }
warn() { echo -e "\033[1;33m!!! $*\033[0m"; }

send_tg_msg() {
  [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ] && return 0
  curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TG_CHAT_ID}" --data-urlencode "text=$1" \
    -d "parse_mode=HTML" -d "disable_web_page_preview=true" >/dev/null
}

send_tg_file() {
  [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ] && return 0
  [ -f "$1" ] || return 0
  curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TG_CHAT_ID}" -F "document=@$1" >/dev/null
}

die() {
  echo -e "\033[1;31m!!! $*\033[0m"
  send_tg_msg "❌ <b>${BUILD_TARGET} ${ANDROID_VERSION} build FAILED</b>
• Device: ${DEVICE}
• Reason: $*"
  exit 1
}

format_dur() { printf "%02d h %02d m %02d s" $(($1/3600)) $((($1%3600)/60)) $(($1%60)); }

# --------------------- GOFILE UPLOAD ----------------------
# echoes "<name>|<size>|<link>" on success, "FAILED" otherwise
gofile_upload() {
  local FILE="$1"
  [ -f "$FILE" ] || { echo "MISSING"; return 1; }

  local BEST
  BEST=$(curl -s https://api.gofile.io/servers | grep -oP '(?<="name":")[^"]*' | head -n 1)
  [ -z "$BEST" ] && BEST="store3"

  local NAME SIZE RESP LINK
  NAME="${FILE##*/}"; SIZE=$(du -h "$FILE" | cut -f1)
  log "Uploading ${NAME} (${SIZE}) via ${BEST} ..."
  RESP=$(curl -# -F "file=@${FILE}" "https://${BEST}.gofile.io/contents/uploadfile")
  LINK=$(echo "$RESP" | grep -oP '"downloadPage":"\K[^"]+')
  if [ -n "$LINK" ]; then
    echo "${NAME}|${SIZE}|${LINK}"
  else
    echo "FAILED"
    return 1
  fi
}

# ------------------------- BUILD --------------------------
build() {
  send_tg_msg "⚙️ <b>${BUILD_TARGET} ${ANDROID_VERSION} build started</b>
• Device: ${DEVICE}
• Server: foss.crave.io
• Start: $(date '+%Y-%m-%d %H:%M:%S %Z')"

  log "Clean previous device/kernel/vendor dirs"
  rm -rf .repo/local_manifests device/sony vendor/sony kernel/sony

  log "repo init: ${MANIFEST_URL} (${MANIFEST_BRANCH})"
  repo init -u "${MANIFEST_URL}" -b "${MANIFEST_BRANCH}" --git-lfs --depth=1 \
    || die "repo init failed"

  if [ -f /opt/crave/resync.sh ]; then
    log "Running Crave resync"
    /opt/crave/resync.sh
  fi

  log "repo sync (this can take a while)"
  repo sync -c --force-sync -j"$(nproc)" 2>&1 | tee /tmp/sync.log
  [ "${PIPESTATUS[0]}" -eq 0 ] || die "repo sync failed (see /tmp/sync.log)"

  log "source build/envsetup.sh && lunch ${LUNCH_TARGET}"
  # shellcheck disable=SC1091
  source build/envsetup.sh || die "envsetup failed"
  lunch "${LUNCH_TARGET}" || die "lunch failed"
  m installclean

  log "Building (kernel 5.4 from source + full AOSP)"
  m -j"$(nproc)" 2>&1 | tee /tmp/build.log
  local ST=${PIPESTATUS[0]}
  if [ "${ST}" -ne 0 ]; then
    mkdir -p out 2>/dev/null
    cp /tmp/build.log out/error.log 2>/dev/null
    send_tg_file "out/error.log"
    die "build failed (exit ${ST})"
  fi

  # --------------------- ARTIFACTS ------------------------
  log "Collecting artifacts from ${OUT}"
  local FILES=()
  for f in boot.img dtbo.img vbmeta.img system.img system_ext.img product.img vendor.img odm.img; do
    [ -f "${OUT}/${f}" ] && FILES+=("${OUT}/${f}")
  done
  local ZIP
  ZIP=$(ls -t "${OUT}"/*"${DEVICE}"*.zip 2>/dev/null | head -n1)
  [ -n "${ZIP}" ] && FILES+=("${ZIP}")

  [ ${#FILES[@]} -gt 0 ] || die "no artifacts found in ${OUT}"

  log "Uploading ${#FILES[@]} artifact(s) to GoFile"
  local REPORT=""
  for f in "${FILES[@]}"; do
    local R
    R=$(gofile_upload "$f")
    if [ "${R}" != "FAILED" ] && [ "${R}" != "MISSING" ]; then
      IFS='|' read -r N S L <<< "${R}"
      REPORT+="
• <b>${N}</b> (${S}): ${L}"
    fi
  done

  local DUR=$(( $(date +%s) - START_TIME ))
  send_tg_msg "✅ <b>${BUILD_TARGET} ${ANDROID_VERSION} build finished</b>
• Device: ${DEVICE}
• Duration: $(format_dur "${DUR}")
• Artifacts:${REPORT}"
  log "Done in $(format_dur "${DUR}")"
}

build
