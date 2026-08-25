#!/usr/bin/env bash
set -Eeuo pipefail

# Temporary, non-destructive Niri installer/recovery helper for Kubuntu/Ubuntu 24.04.
# Installs Niri v26.04 beside Plasma. KDE/Plasma is NOT uninstalled.
# Large Rust/build data is kept on /mnt/data to avoid filling the OS partition.

NIRI_TAG="v26.04"
SAT_TAG="v0.8.2"
DATA_MOUNT="/mnt/data"
ME="$(id -un)"
MYGROUP="$(id -gn)"
WORK_ROOT="$DATA_MOUNT/niri24-$ME"
BUILD_ROOT="$WORK_ROOT/src"
TARGET_ROOT="$WORK_ROOT/target"
export CARGO_HOME="$WORK_ROOT/cargo"
export RUSTUP_HOME="$WORK_ROOT/rustup"
export TMPDIR="$WORK_ROOT/tmp"
export CARGO_TARGET_DIR="$TARGET_ROOT"
export PATH="$CARGO_HOME/bin:$PATH"
LOG="$HOME/niri24-install.log"

exec > >(tee -a "$LOG") 2>&1

stage() { printf '\n===== %s =====\n' "$*"; }
fail() { printf '\nERROR: %s\nLog: %s\n' "$*" "$LOG" >&2; exit 1; }
trap 'fail "installation stopped near line $LINENO"' ERR

stage "1/10 Preflight and data partition"
echo "User: $ME"
echo "Ubuntu: $(. /etc/os-release; echo "${VERSION_ID:-unknown}")"
echo "Kernel: $(uname -r)"
echo "GPUs:"
lspci | grep -Ei 'VGA|3D|Display' || true

mountpoint -q "$DATA_MOUNT" || fail "$DATA_MOUNT is not mounted"
FREE_KB="$(df -Pk "$DATA_MOUNT" | awk 'NR==2 {print $4}')"
FREE_GB=$((FREE_KB / 1024 / 1024))
echo "Build/storage location: $WORK_ROOT"
echo "Free on $DATA_MOUNT: about ${FREE_GB} GiB"
(( FREE_KB >= 8 * 1024 * 1024 )) || fail "need at least 8 GiB free on $DATA_MOUNT"

sudo mkdir -p "$WORK_ROOT" "$BUILD_ROOT" "$TARGET_ROOT" "$CARGO_HOME" "$RUSTUP_HOME" "$TMPDIR"
sudo chown -R "$ME:$MYGROUP" "$WORK_ROOT"

if [[ -r /sys/module/nvidia_drm/parameters/modeset ]]; then
    NVIDIA_MODESET="$(cat /sys/module/nvidia_drm/parameters/modeset)"
    echo "NVIDIA DRM modeset: $NVIDIA_MODESET"
else
    NVIDIA_MODESET="not-loaded"
    echo "NVIDIA DRM modeset: nvidia_drm not currently loaded"
fi

stage "2/10 Disable the known broken Celestia apt source"
# The current machine has an obsolete celestiaproject.space Noble source that makes
# apt update fail with 404/No Release file. Disable only source files containing
# that exact hostname, and keep them under a reversible .disabled-by-niri24 name.
sudo -v
shopt -s nullglob
for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    if sudo grep -qi 'celestiaproject\.space' "$f"; then
        disabled="$f.disabled-by-niri24"
        if [[ ! -e "$disabled" ]]; then
            echo "Disabling broken source: $f"
            sudo mv "$f" "$disabled"
        fi
    fi
done
# Rare case: source was manually placed in the main sources.list. Back up first,
# then comment only matching traditional deb lines.
if [[ -f /etc/apt/sources.list ]] && sudo grep -qi 'celestiaproject\.space' /etc/apt/sources.list; then
    sudo cp -an /etc/apt/sources.list /etc/apt/sources.list.niri24-backup
    sudo sed -i '/celestiaproject\.space/ s/^[[:space:]]*deb /# disabled-by-niri24 deb /' /etc/apt/sources.list
    echo "Disabled Celestia entry in /etc/apt/sources.list (backup kept)."
fi

stage "3/10 Packages"
sudo apt-get update
sudo apt-get install -y \
    git curl ca-certificates build-essential gcc clang pkg-config \
    libudev-dev libgbm-dev libxkbcommon-dev libegl1-mesa-dev \
    libwayland-dev libinput-dev libdbus-1-dev libsystemd-dev \
    libseat-dev libpipewire-0.3-dev libpango1.0-dev libdisplay-info-dev \
    libxcb1-dev libxcb-cursor-dev xwayland \
    waybar fuzzel alacritty swaylock mako-notifier swaybg \
    xdg-desktop-portal-gtk xdg-desktop-portal-gnome gnome-keyring \
    policykit-1-gnome wl-clipboard brightnessctl playerctl
# Do not leave downloaded .deb files consuming the root filesystem.
sudo apt-get clean

stage "4/10 Rust on data partition"
if [[ ! -x "$CARGO_HOME/bin/rustup" ]]; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --profile minimal --no-modify-path
fi
rustup update stable
rustup default stable
rustc --version
cargo --version

echo "CARGO_HOME=$CARGO_HOME"
echo "RUSTUP_HOME=$RUSTUP_HOME"
echo "CARGO_TARGET_DIR=$CARGO_TARGET_DIR"

stage "5/10 Build Niri $NIRI_TAG on data partition"
rm -rf "$BUILD_ROOT/niri" "$TARGET_ROOT"
mkdir -p "$BUILD_ROOT" "$TARGET_ROOT"
git clone --depth 1 --branch "$NIRI_TAG" https://github.com/niri-wm/niri.git "$BUILD_ROOT/niri"
cargo build --release --locked --manifest-path "$BUILD_ROOT/niri/Cargo.toml"

stage "6/10 Install Niri session"
sudo -v
sudo install -Dm755 "$TARGET_ROOT/release/niri" /usr/local/bin/niri
sudo install -Dm755 "$BUILD_ROOT/niri/resources/niri-session" /usr/local/bin/niri-session
sudo install -Dm644 "$BUILD_ROOT/niri/resources/niri.desktop" /usr/local/share/wayland-sessions/niri.desktop
sudo install -Dm644 "$BUILD_ROOT/niri/resources/niri-portals.conf" /usr/local/share/xdg-desktop-portal/niri-portals.conf

sed 's|^ExecStart=niri --session$|ExecStart=/usr/local/bin/niri --session|' \
    "$BUILD_ROOT/niri/resources/niri.service" > "$BUILD_ROOT/niri.service"
sudo install -Dm644 "$BUILD_ROOT/niri.service" /etc/systemd/user/niri.service
sudo install -Dm644 "$BUILD_ROOT/niri/resources/niri-shutdown.target" /etc/systemd/user/niri-shutdown.target
systemctl --user daemon-reload

stage "7/10 Build Xwayland Satellite $SAT_TAG on data partition"
rm -rf "$BUILD_ROOT/xwayland-satellite"
git clone --depth 1 --branch "$SAT_TAG" https://github.com/Supreeeme/xwayland-satellite.git "$BUILD_ROOT/xwayland-satellite"
cargo build --release --locked --manifest-path "$BUILD_ROOT/xwayland-satellite/Cargo.toml"
sudo install -Dm755 "$TARGET_ROOT/release/xwayland-satellite" /usr/local/bin/xwayland-satellite

stage "8/10 Niri desktop configuration"
mkdir -p "$HOME/.config/niri" "$HOME/.config/waybar" "$HOME/.local/bin"

if [[ ! -e "$HOME/.config/niri/config.kdl" ]]; then
    cp "$BUILD_ROOT/niri/resources/default-config.kdl" "$HOME/.config/niri/config.kdl"
fi

if ! grep -q 'sky-status niri helper' "$HOME/.config/niri/config.kdl"; then
    cat >> "$HOME/.config/niri/config.kdl" <<'KDL'

// sky-status niri helper: basic desktop services
spawn-at-startup "mako"
spawn-at-startup "swaybg" "-c" "#202124"
spawn-at-startup "waybar"
spawn-at-startup "xwayland-satellite"
spawn-at-startup "/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1"
KDL
fi

# Preserve the already-installed backend if it exists. Only copy from this repo
# when the repo's version is present and executable.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/sky-status" ]]; then
    install -Dm755 "$SCRIPT_DIR/sky-status" "$HOME/.local/bin/sky-status"
fi

if [[ ! -e "$HOME/.config/waybar/config" && ! -e "$HOME/.config/waybar/config.jsonc" ]]; then
    cat > "$HOME/.config/waybar/config" <<'JSON'
{
  "layer": "top",
  "position": "top",
  "height": 30,
  "spacing": 10,
  "modules-left": ["custom/sky-status"],
  "modules-center": ["clock"],
  "modules-right": ["network", "pulseaudio", "battery", "tray"],
  "custom/sky-status": {
    "exec": "$HOME/.local/bin/sky-status",
    "interval": 300,
    "tooltip": false
  },
  "clock": {"format": "{:%a %d %b  %H:%M}"},
  "network": {
    "format-wifi": "Wi-Fi {signalStrength}%",
    "format-ethernet": "LAN",
    "format-disconnected": "Offline"
  },
  "pulseaudio": {"format": "Vol {volume}%"},
  "battery": {"format": "Bat {capacity}%"}
}
JSON
fi

if [[ ! -e "$HOME/.config/waybar/style.css" ]]; then
    cat > "$HOME/.config/waybar/style.css" <<'CSS'
* {
  font-family: sans-serif;
  font-size: 13px;
}
window#waybar {
  background: rgba(28, 29, 32, 0.94);
  color: #e8eaed;
}
#custom-sky-status, #clock, #network, #pulseaudio, #battery, #tray {
  padding: 0 8px;
}
CSS
fi

stage "9/10 NVIDIA safeguards"
if command -v nvidia-smi >/dev/null 2>&1 || lspci | grep -qi nvidia; then
    sudo mkdir -p /etc/nvidia/nvidia-application-profiles-rc.d
    sudo tee /etc/nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool-in-wayland-compositors.json >/dev/null <<'JSON'
{
  "rules": [
    {
      "pattern": {"feature": "procname", "matches": "niri"},
      "profile": "Limit Free Buffer Pool On Wayland Compositors"
    }
  ],
  "profiles": [
    {
      "name": "Limit Free Buffer Pool On Wayland Compositors",
      "settings": [{"key": "GLVidHeapReuseRatio", "value": 0}]
    }
  ]
}
JSON

    if [[ "$NVIDIA_MODESET" != "Y" && "$NVIDIA_MODESET" != "1" ]]; then
        echo 'options nvidia-drm modeset=1' | sudo tee /etc/modprobe.d/nvidia-drm-modeset.conf >/dev/null
        sudo update-initramfs -u
        echo "Enabled nvidia-drm modeset=1 for next boot."
    else
        echo "NVIDIA DRM modesetting is already enabled."
    fi
fi

stage "10/10 Make SDDM start Niri"
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/99-niri-recovery.conf >/dev/null <<SDDM
[Autologin]
User=$ME
Session=niri.desktop
SDDM

printf '\nNiri installation complete.\n'
printf 'Niri: %s\n' "$(/usr/local/bin/niri --version 2>/dev/null || true)"
printf 'Xwayland Satellite: %s\n' "$(/usr/local/bin/xwayland-satellite --version 2>/dev/null || true)"
printf 'Large build/Rust data: %s\n' "$WORK_ROOT"
printf 'Log: %s\n' "$LOG"
printf '\nAfter reboot: Super+T = terminal, Super+D = launcher, Super+Shift+E = exit Niri.\n'
printf 'If Niri itself black-screens, Ctrl+Alt+F3 still gets you a TTY.\n\n'

read -r -p "Reboot into Niri now? [Y/n] " answer
case "${answer:-Y}" in
    [nN]*) echo "Not rebooting." ;;
    *) sudo reboot ;;
esac
