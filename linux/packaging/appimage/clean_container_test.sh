#!/usr/bin/env bash
# Verifies the AppImage is self-contained w.r.t. libmpv: runs it in a minimal
# container that has GTK (any host able to run a Flutter app has it) but NO
# libmpv. Success = MediaKit.ensureInitialized() finds the bundled libmpv and
# the app survives until the timeout kills it.
#
# The container image must match the distro the AppImage was BUILT on: glibc
# cannot be bundled, so an AppImage's minimum host baseline is the glibc of
# its build machine (e.g. built on ubuntu-24.04 CI → runs on Ubuntu 24.04+/
# Debian 13+; a debian:bookworm container with glibc 2.36 would fail with
# "GLIBC_2.38 not found" regardless of the libmpv bundling being correct).
# By default the build host's own distro:version is used; override with arg 2.
#
# Usage: sudo bash clean_container_test.sh <AppImage> [docker-image]
set -euo pipefail

APPIMAGE="${1:?usage: clean_container_test.sh <path-to-AppImage> [docker-image]}"
APPIMAGE="$(readlink -f "$APPIMAGE")"

if [ -n "${2:-}" ]; then
    IMAGE="$2"
else
    IMAGE="$(. /etc/os-release && echo "${ID}:${VERSION_ID}")"
fi
echo "--- test container: $IMAGE (must match the AppImage's build distro)"

docker run --rm -v "$(dirname "$APPIMAGE"):/dist:ro" "$IMAGE" bash -c "
set -e
apt-get update -qq >/dev/null
# Provide what the AppImage intentionally does NOT bundle (see
# generate_make_config.sh): the glvnd/mesa GL stack — libgl1/libglx-mesa0/
# libegl1/libgles2 (glvnd dispatch + mesa GLX vendor) and libgl1-mesa-dri
# (DRI driver, pulls libgbm1/libdrm2/libglapi). libasound2-plugins supplies
# the host ALSA plugin .so's that the BUNDLED libasound dlopens by config
# (every real desktop has them; without it the container logs a non-fatal
# hook error). No mpv-specific package is installed — that is the point.
apt-get install -y -qq \
    libgtk-3-0 libstdc++6 \
    libgl1 libglx-mesa0 libegl1 libgles2 libgl1-mesa-dri \
    libasound2-plugins \
    xvfb xauth >/dev/null
echo '--- libmpv in container:' \$(ldconfig -p | grep -c libmpv || true) '(0 = clean test)'
cd /tmp
cp '/dist/$(basename "$APPIMAGE")' app.AppImage
chmod +x app.AppImage
./app.AppImage --appimage-extract >/dev/null
echo '--- launching under xvfb for 15s ---'
set +e
timeout 15 xvfb-run -a squashfs-root/AppRun >/tmp/out.log 2>&1
rc=\$?
set -e
head -30 /tmp/out.log
echo \"--- exit code: \$rc (124/143 = survived until timeout — OK) ---\"
# Genuine self-containment failures only. ALSA card/mixer/hook messages are
# NOT matched: a headless container has no sound card, and audio output is
# exercised at play time, not at MediaKit.ensureInitialized (which is all
# this test gates). 'MediaKit.ensureInitialized' / 'Cannot find libmpv'
# appear only in the failure stack trace + error banner, never on success.
if grep -qE 'Cannot find libmpv|MediaKit\.ensureInitialized|No provider of|GLIBC_[0-9]' /tmp/out.log; then
    echo 'FAIL: bundled libraries did not load cleanly'; exit 1
fi
if [ \$rc -ne 124 ] && [ \$rc -ne 143 ]; then
    echo \"FAIL: app crashed/exited early (rc=\$rc)\"; exit 1
fi
echo 'PASS: AppImage is self-contained w.r.t. libmpv (ALSA card warnings under Xvfb are expected)'
"
