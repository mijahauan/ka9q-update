#!/bin/bash
set -e

# Default to current directory if not provided, or a sensible default if called from elsewhere
TARGET_DIR="${1:-$PWD}"

echo "=== ka9q-radio & ka9q-web Installer ==="
echo "Target Directory: $TARGET_DIR"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Creating target directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi

RADIO_DIR="$TARGET_DIR/ka9q-radio"
WEB_DIR="$TARGET_DIR/ka9q-web"
ONION_DIR="$TARGET_DIR/onion"

# 0. Install Dependencies
echo "[+] Installing Dependencies..."
# List from INSTALL.md + extras requested + Onion dependencies
DEPENDENCIES="git avahi-utils build-essential make gcc libairspy-dev libairspyhf-dev \
libavahi-client-dev libbsd-dev libfftw3-dev libhackrf-dev libiniparser-dev \
libncurses5-dev libopus-dev librtlsdr-dev libusb-1.0-0-dev libusb-dev \
portaudio19-dev libasound2-dev uuid-dev rsync libogg-dev libsamplerate-dev \
libliquid-dev libncursesw5-dev libhackrf-dev libbladerf-dev libliquid-dev \
sox libsox-fmt-all opus-tools flac tcpdump wireshark \
libgnutls28-dev libgcrypt-dev cmake"

echo "    Updates apt cache..."
sudo apt update
echo "    Installing packages..."
sudo apt install -y $DEPENDENCIES

# 1. Check/Update Repositories
echo "[+] Checking Repositories..."

# ka9q-radio
if [ -d "$RADIO_DIR" ]; then
    echo "    Updating ka9q-radio..."
    git -C "$RADIO_DIR" pull
else
    echo "    Cloning ka9q-radio..."
    git clone https://github.com/ka9q/ka9q-radio.git "$RADIO_DIR"
fi

# ka9q-web
if [ -d "$WEB_DIR" ]; then
    echo "    Updating ka9q-web..."
    git -C "$WEB_DIR" pull
else
    echo "    Cloning ka9q-web..."
    git clone https://github.com/scottnewell/ka9q-web.git "$WEB_DIR"
fi

# onion
if [ -d "$ONION_DIR" ]; then
    echo "    Updating onion..."
    git -C "$ONION_DIR" pull
else
    echo "    Cloning onion..."
    git clone https://github.com/davidmoreno/onion.git "$ONION_DIR"
fi

# 2. Build Onion Framework
echo "[+] Building Onion Framework..."
cd "$ONION_DIR"
mkdir -p build
cd build
echo "    Configuring Onion (Light Version)..."
cmake -DONION_USE_PAM=false -DONION_USE_PNG=false -DONION_USE_JPEG=false \
      -DONION_USE_XML2=false -DONION_USE_SYSTEMD=false -DONION_USE_SQLITE3=false \
      -DONION_USE_REDIS=false -DONION_USE_GC=false -DONION_USE_TESTS=false \
      -DONION_EXAMPLES=false -DONION_USE_BINDINGS_CPP=false .. > cmake_output.txt 2>&1

# Verify SSL support
if grep -q "SSL support is compiled in" cmake_output.txt; then
    echo "    SSL support verified."
else
    echo "Error: SSL support NOT found in Onion build configuration."
    cat cmake_output.txt
    exit 1
fi

echo "    Compiling Onion..."
make -j$(nproc)
echo "    Installing Onion..."
sudo make install
sudo ldconfig

# 3. Detect Configuration
echo "[+] Detecting Configuration..."
# Try to find running radiod instance first
RUNNING_INSTANCE=$(systemctl list-units --type=service --state=running --no-legend "radiod@*" | cut -d' ' -f1 | head -n1)

if [ -n "$RUNNING_INSTANCE" ]; then
    INSTANCE_NAME=$(echo "$RUNNING_INSTANCE" | sed -E 's/radiod@(.*)\.service/\1/')
    echo "    Found running service: $INSTANCE_NAME"
    CONFIG_FILE="/etc/radio/radiod@${INSTANCE_NAME}.conf"
else
    # Find first conf file in /etc/radio
    CONFIG_FILE=$(ls /etc/radio/radiod@*.conf 2>/dev/null | head -n1)
    if [ -z "$CONFIG_FILE" ]; then
        echo "Error: No configuration found in /etc/radio."
        exit 1
    fi
    INSTANCE_NAME=$(basename "$CONFIG_FILE" | sed -E 's/radiod@(.*)\.conf/\1/')
    echo "    Found configuration file for instance: $INSTANCE_NAME"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE does not exist."
    exit 1
fi

# Extract status address (handles 'status = value # comment')
STATUS_ADDR=$(awk -F'=' '/^\s*status\s*=/ {print $2}' "$CONFIG_FILE" | awk '{print $1}')

if [ -z "$STATUS_ADDR" ]; then
    echo "Error: Could not find 'status =' definition in $CONFIG_FILE"
    exit 1
fi
echo "    Using status address: $STATUS_ADDR"

# 4. Build and Install ka9q-radio
echo "[+] Building and Installing ka9q-radio..."
cd "$RADIO_DIR"
make -j$(nproc)
sudo make install

# 5. Build and Install ka9q-web
echo "[+] Building and Installing ka9q-web..."
cd "$WEB_DIR"
make -j$(nproc)
sudo make install

# 6. Configure service for ka9q-web
echo "[+] Configuring ka9q-web service..."

TEMP_SERVICE_FILE="/tmp/ka9q-web.service"
KA9Q_WEB_SERVICE_SRC="$WEB_DIR/ka9q-web.service"

# Copy service file to temp to modify
cp "$KA9Q_WEB_SERVICE_SRC" "$TEMP_SERVICE_FILE"

# Update ExecStart with discovered status address
# Use | as delimiter to avoid issues with standard slashes in paths
sed -i "s|ExecStart=.*|ExecStart=/usr/local/sbin/ka9q-web -m $STATUS_ADDR -p 8081|" "$TEMP_SERVICE_FILE"

echo "    Installing service file to /etc/systemd/system/ka9q-web.service..."
sudo cp "$TEMP_SERVICE_FILE" /etc/systemd/system/ka9q-web.service
sudo systemctl daemon-reload

# 7. Restart Services
echo "[+] Restarting Services..."
echo "    Restarting radiod@$INSTANCE_NAME..."
sudo systemctl restart "radiod@$INSTANCE_NAME"

echo "    Enabling and starting ka9q-web..."
sudo systemctl enable ka9q-web
sudo systemctl restart ka9q-web

echo "=== Installation Complete ==="
echo "ka9q-web service is active."
