#!/usr/bin/env bash
set -euo pipefail

# Must be run under sudo from the user you want VNC to run as
if [[ $EUID -ne 0 || -z "${SUDO_USER:-}" || "$SUDO_USER" = "root" ]]; then
  echo "Usage: sudo $0"
  exit 1
fi

USER="$SUDO_USER"
HOME_DIR="$(getent passwd "$USER" | cut -d: -f6)"
DISPLAY_NUM="1"  # you can change to 2, 3, etc.

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
[ -f ~/.Xresources ] && xrdb ~/.Xresources
startxfce4 &
EOF
chown "$USER":"$USER" "$HOME_DIR/.vnc/xstartup"
chmod +x "$HOME_DIR/.vnc/xstartup"

echo "Setting VNC password (you’ll be prompted)..."
sudo -u "$USER" vncpasswd

SERVICE_PATH=/etc/systemd/system/vncserver@.service

echo "Creating corrected systemd unit at $SERVICE_PATH..."
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=TigerVNC Server for display :%i
After=network.target

[Service]
Type=forking
User=$USER
PAMName=login
PIDFile=$HOME_DIR/.vnc/%H\:%i.pid

# kill any existing instance on :%i
ExecStartPre=-/usr/bin/vncserver -kill :%i

# note the leading colon before %i
ExecStart=/usr/bin/vncserver :%i
ExecStop=/usr/bin/vncserver -kill :%i

Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "Enabling and starting VNC on display :${DISPLAY_NUM}..."
systemctl daemon-reload
systemctl enable vncserver@"${DISPLAY_NUM}".service
systemctl start  vncserver@"${DISPLAY_NUM}".service

echo "You can now change your cursor theme in XFCE Settings → Mouse and Touchpad → Theme."

# Optional TLS via Let’s Encrypt
read -p "Enable TLS encryption with Let’s Encrypt? (y/N): " yn
if [[ $yn =~ ^[Yy] ]]; then
  echo "Installing certbot..."
  apt install -y certbot

  read -p "Enter the fully qualified domain name (must point to this server): " DOMAIN
  certbot certonly --standalone --agree-tos --no-eff-email \
    -m "admin@$DOMAIN" -d "$DOMAIN"

  echo "Updating systemd unit to use TLSVnc..."
  sed -i "s|ExecStart=/usr/bin/vncserver :%i|ExecStart=/usr/bin/vncserver :%i -SecurityTypes TLSVnc,VncAuth \
  -X509Cert=/etc/letsencrypt/live/$DOMAIN/fullchain.pem \
  -X509Key=/etc/letsencrypt/live/$DOMAIN/privkey.pem|" \
    "$SERVICE_PATH"

  systemctl daemon-reload
  systemctl restart vncserver@"${DISPLAY_NUM}".service

  echo "TLS encryption enabled: connect with a VNC client that trusts Let's Encrypt."
fi

echo
echo "Setup complete! Connect your VNC client to <your-server-ip>:${DISPLAY_NUM}"
