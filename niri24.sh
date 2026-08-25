#!/usr/bin/env bash
set -Eeuo pipefail

# Temporary, non-destructive Niri installer/recovery helper for Kubuntu/Ubuntu 24.04.
# Installs Niri v26.04 beside Plasma and makes SDDM autologin to Niri.
# It does NOT uninstall Plasma or KDE applications.

NIRI_TAG="v26.04"
SAT_TAG="v0.8.2"
BUILD_ROOT="$HOME/.cache/niri24-build"
LOG="$HOME/niri24-install.log"
ME="$(id -un)"

exec > >(tee -a "$LOG") 2>&1

stage() { printf '\n===== %s =====\n' "$*"; }
fail() { printf '\nERROR: %s\nLog: %s\n' "$*" "$LOG" >&2; exit 1; }
trap 'fail "installation stopped near line $LINENO"' ERR

stage "1/9 Preflight"
echo "User: $ME"
echo "Ubuntu: $(. /etc/os-release; echo "${VERSION_ID:-unknown}")"
echo "Kernel: $(uname -r)"
echo "GPUs:"
lspci | grep -Ei 'VGA|3D|Display' || true

if [[ -r /sys/module/nvidia_drm/parameters/modeset ]]; then
    NVIDIA_MODESET="$(cat /sys/module/nvidia_drm/parameters/modeset)"
    echo "NVIDIA DRM modeset: $NVIDIA_MODESET"
else
    NVIDIA_MODESET="not-loaded"
    echo "NVIDIA DRM modeset: nvidia_drm not currently loaded"
fi

stage "2/9 Packages"
sudo -v
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

stage "3/9 Rust"
if [[ ! -x "$HOME/.cargo/bin/rustup" ]]; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --profile minimal
fi
# shellcheck disable=SC1091
source "$HOME/.cargo/env"
rustup update stable
rustup default stable
rustc --version
cargo --version

stage "4/9 Build Niri $NIRI_TAG"
rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"
git clone --depth 1 --branch "$NIRI_TAG" https://github.com/niri-wm/niri.git "$BUILD_ROOT/niri"
cargo build --release --manifest-path "$BUILD_ROOT/niri/Cargo.toml"

stage "5/9 Install Niri session"
sudo -v
sudo install -Dm755 "$BUILD_ROOT/niri/target/release/niri" /usr/local/bin/niri
sudo install -Dm755 "$BUILD_ROOT/niri/resources/niri-session" /usr/local/bin/niri-session
sudo install -Dm644 "$BUILD_ROOT/niri/resources/niri.desktop" /usr/local/share/wayland-sessions/niri.desktop
sudo install -Dm644 "$BUILD_ROOT/niri/resources/niri-portals.conf" /usr/local/share/xdg-desktop-portal/niri-portals.conf

sed 's|^ExecStart=niri --session$|ExecStart=/usr/local/bin/niri --session|' \
    "$BUILD_ROOT/niri/resources/niri.service" > "$BUILD_ROOT/niri.service"
sudo install -Dm644 "$BUILD_ROOT/niri.service" /etc/systemd/user/niri.service
sudo install -Dm644 "$BUILD_ROOT/niri/resources/niri-shutdown.target" /etc/systemd/user/niri-shutdown.target
systemctl --user daemon-reload

stage "6/9 Build Xwayland Satellite $SAT_TAG"
git clone --depth 1 --branch "$SAT_TAG" https://github.com/Supreeeme/xwayland-satellite.git "$BUILD_ROOT/xwayland-satellite"
cargo build --release --manifest-path "$BUILD_ROOT/xwayland-satellite/Cargo.toml"
sudo install -Dm755 "$BUILD_ROOT/xwayland-satellite/target/release/xwayland-satellite" /usr/local/bin/xwayland-satellite

stage "7/9 Niri desktop configuration"
mkdir -p "$HOME/.config/niri" "$HOME/.config/waybar" "$HOME/.local/bin"

if [[ ! -e "$HOME/.config/niri/config.kdl" ]]; then
    cp "$BUILD_ROOT/niri/resources/default-config.kdl" "$HOME/.config/niri/config.kdl"
fi

if ! grep -q 'sky-status niri helper' "$HOME/.config/niri/config.kdl"; then
    cat >> "$HOME/.config/niri/config.kdl" <<'KDL'

// sky-status niri helper: basic desktop services
spawn-at-startup "mako"
spawn-at-startup "swaybg" "-c" "#202124"
KDL
fi

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

stage "8/9 NVIDIA safeguards"
if command -v nvidia-smi >/dev/null 2>&1 || lspci | grep -qi nvidia; then
    sudo mkdir -p /etc/nvidia/nvidia-application-profiles-rc.d
    sudo tee /etc/nvidia/nvidia-application-profiles-rc.d/50-niri-vram.json >/dev/null <<'JSON'
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
    fi
fi

stage "9/9 Make SDDM start Niri"
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/99-niri-recovery.conf >/dev/null <<SDDM
[Autologin]
User=$ME
Session=niri.desktop
SDDM

printf '\nNiri installation complete.\n'
printf 'Niri: %s\n' "$(/usr/local/bin/niri --version 2>/dev/null || true)"
printf 'Xwayland Satellite: %s\n' "$(/usr/local/bin/xwayland-satellite --version 2>/dev/null || true)"
printf 'Log: %s\n' "$LOG"
printf '\nAfter reboot: Super+T = terminal, Super+D = launcher, Super+Shift+E = exit Niri.\n'
printf 'If Niri itself black-screens, Ctrl+Alt+F3 still gets you a TTY.\n\n'

read -r -p "Reboot into Niri now? [Y/n] " answer
case "${answer:-Y}" in
    [nN]*) echo "Not rebooting." ;;
    *) sudo reboot ;;
esac
