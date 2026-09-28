# crave_script — Tama-5-4-lineage

Crave build script for **AOSP Android 16 (r4)** on Sony Tama (SDM845: akari /
XZ2) with **kernel 5.4** (built from source) + retrofit dynamic partitions.

## Usage on Crave
Use the script as the build command:
```sh
bash aosp.sh
```

Config at the top of `aosp.sh`:
- `DEVICE=akari`
- `LUNCH_TARGET=aosp_h8266-userdebug` (XZ2 Dual; use `aosp_h8216` for XZ2)
- `MANIFEST_URL=https://github.com/Tama-5-4-lineage/manifest` (branch `main`)

## What it does
1. Clean local dirs, `repo init` from the org manifest, `/opt/crave/resync.sh`, `repo sync`.
2. `source build/envsetup.sh`, `lunch`, `m installclean`, full `m`.
3. Upload artifacts to **GoFile** (`api.gofile.io`): `boot.img`, `dtbo.img`,
   `vbmeta.img`, `system.img`, `system_ext.img`, `product.img`, `vendor.img`,
   `odm.img` and the OTA/ROM zip (if present).

## Progress / notifications
- Colored timestamped `>>>` progress lines for each step; raw `repo sync` and
  `m` output is streamed and also saved to `/tmp/sync.log` / `/tmp/build.log`.
- Optional **Telegram**: set env vars before running
  `TG_BOT_TOKEN` and `TG_CHAT_ID` and it will send start/finish/failure + the
  GoFile links (no token is stored in this repo).

## Notes
- All repos are public (Crave FOSS requirement).
- `fastboot boot` is not supported on Sony -> flash images normally.
