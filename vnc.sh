#!/usr/bin/env bash
set -euo pipefail

# Must be run under sudo from the user you want VNC to run as
if [[ $EUID -ne 0 || -z "${SUDO_USER:-}" || "$SUDO_USER" = "root" ]]; then
  echo "Usage: sudo $0"
  exit 1
fi

USER="$SUDO_USER"
HOME_DIR="$(getent passwd "$USER" | cut -d: -f6)"
DISPLAY_NUM="1"           # you can change to :2, :3, etc.

echo "Installing XFCE, TigerVNC, cursor themes..."
apt update
DEBIAN_FRONTEND=noninteractive apt install -y \
  xfce4 xfce4-goodies xorg dbus-x11 x11-xserver-utils \
  tigervnc-standalone-server tigervnc-common \
  xcursor-themes

echo "Creating VNC startup script for $USER..."
sudo -u "$USER" mkdir -p "$HOME_DIR/.vnc"
cat > "$HOME_DIR/.vnc/xstartup" <<'EOF'
#!/bin/sh
# Load X resources, then start XFCE
[ -f ~/.Xresources ] && xrdb ~/.Xresources
startxfce4 &
EOF
chown "$USER":"$USER" "$HOME_DIR/.vnc/xstartup"
chmod +x "$HOME_DIR/.vnc/xstartup"

echo "Setting VNC password (you’ll be prompted)..."
sudo -u "$USER" vncpasswd

echo "Creating systemd unit at /etc/systemd/system/vncserver@.service..."
cat > /etc/systemd/system/vncserver@.service <<EOF
[Unit]
Description=TigerVNC Server for %i
After=network.target

[Service]
Type=forking
User=$USER
PAMName=login
# PID file is created by tigervncserver
PIDFile=$HOME_DIR/.vnc/%H:%i.pid
ExecStartPre=-/usr/bin/vncserver -kill %i
ExecStart=/usr/bin/vncserver %i
ExecStop=/usr/bin/vncserver -kill %i
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "Enabling and starting VNC on display :${DISPLAY_NUM}..."
systemctl daemon-reload
systemctl enable vncserver@"${DISPLAY_NUM}".service
systemctl start  vncserver@"${DISPLAY_NUM}".service

echo "Installing cursor themes—you can choose a new cursor via XFCE Settings → Mouse and Touchpad → Theme."
# xcursor-themes is already installed; optionally set a default:
update-alternatives --install /usr/share/icons/default/index.theme x-cursor-theme \
  /usr/share/icons/Adwaita/index.theme 50 >/dev/null 2>&1 || true

# Optional TLS via Let’s Encrypt
read -p "Enable TLS encryption with Let’s Encrypt? (y/N): " yn
if [[ $yn =~ ^[Yy] ]]; then
  echo "Installing certbot..."
  apt install -y certbot

  read -p "Enter the domain (must point to this server): " DOMAIN
  certbot certonly --standalone --agree-tos --no-eff-email \
    -m "admin@$DOMAIN" -d "$DOMAIN"

  echo "Rewriting systemd unit to use TLSVnc..."
  sed -i "s|ExecStart=/usr/bin/vncserver %i|ExecStart=/usr/bin/vncserver -SecurityTypes TLSVnc,VncAuth \
  -X509Cert=/etc/letsencrypt/live/$DOMAIN/fullchain.pem \
  -X509Key=/etc/letsencrypt/live/$DOMAIN/privkey.pem %i|" \
    /etc/systemd/system/vncserver@.service

  systemctl daemon-reload
  systemctl restart vncserver@"${DISPLAY_NUM}".service

  echo "TLS encryption enabled: connect with a VNC client that trusts your Let's Encrypt CA."
fi

echo
echo "Setup complete! Connect your VNC client to <your-server-ip>:${DISPLAY_NUM}"
