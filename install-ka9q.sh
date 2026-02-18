#!/bin/bash
set -e

# Default to current directory if not provided
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
DEPENDENCIES="git avahi-utils build-essential make gcc libairspy-dev libairspyhf-dev \
libavahi-client-dev libbsd-dev libfftw3-dev libhackrf-dev libiniparser-dev \
libncurses5-dev libopus-dev librtlsdr-dev libusb-1.0-0-dev libusb-dev \
portaudio19-dev libasound2-dev uuid-dev rsync libogg-dev libsamplerate-dev \
libliquid-dev libncursesw5-dev libhackrf-dev libbladerf-dev libliquid-dev \
sox libsox-fmt-all opus-tools flac tcpdump wireshark \
libgnutls28-dev libgcrypt-dev cmake"

echo "    Updating apt cache..."
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
    # Using wa2n-code fork which is compatible with latest ka9q-radio
    git clone https://github.com/wa2n-code/ka9q-web.git "$WEB_DIR"
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

# 3. Build and Install ka9q-radio
# MOVED UP: Must be installed before we can check /etc/radio config
echo "[+] Building and Installing ka9q-radio..."
cd "$RADIO_DIR"
make -j$(nproc)
sudo make install

# 4. Detect Configuration
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
        echo "Warning: No configuration found in /etc/radio."
        echo "         You need to create a configuration file before starting the service."
        echo "         A template is available in the repository: radiod@template.conf"
        read -p "Press Enter to continue installation (service start will fail) or Ctrl+C to abort..."
    else
        INSTANCE_NAME=$(basename "$CONFIG_FILE" | sed -E 's/radiod@(.*)\.conf/\1/')
        echo "    Found configuration file for instance: $INSTANCE_NAME"
    fi
fi

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    # Extract status address (handles 'status = value # comment')
    # Using grep and sed for better portability than awk with \s
    STATUS_ADDR=$(grep -E "^[[:space:]]*status[[:space:]]*=" "$CONFIG_FILE" | head -n1 | sed -E 's/^[[:space:]]*status[[:space:]]*=[[:space:]]*([^ #]*).*/\1/')

    if [ -z "$STATUS_ADDR" ]; then
        echo "Error: Could not find 'status =' definition in $CONFIG_FILE"
        exit 1
    fi
    echo "    Using status address: $STATUS_ADDR"
else
    echo "    No valid config found. Skipping status address detection."
fi

# 5. Build and Install ka9q-web
echo "[+] Building and Installing ka9q-web..."
cd "$WEB_DIR"
# Explicitly pass KA9Q_RADIO_DIR to ensure it finds the source/objects correctly
make -j$(nproc) KA9Q_RADIO_DIR="$RADIO_DIR/src"
sudo make install

# 6. Configure service for ka9q-web
echo "[+] Configuring ka9q-web service..."

if [ -n "$STATUS_ADDR" ]; then
    TEMP_SERVICE_FILE="/tmp/ka9q-web.service"
    KA9Q_WEB_SERVICE_SRC="$WEB_DIR/ka9q-web.service"

    # Copy service file to temp to modify
    cp "$KA9Q_WEB_SERVICE_SRC" "$TEMP_SERVICE_FILE"

    # Update ExecStart with discovered status address
    sed -i "s|ExecStart=.*|ExecStart=/usr/local/sbin/ka9q-web -m $STATUS_ADDR -p 8081|" "$TEMP_SERVICE_FILE"

    echo "    Installing service file to /etc/systemd/system/ka9q-web.service..."
    sudo cp "$TEMP_SERVICE_FILE" /etc/systemd/system/ka9q-web.service
    sudo systemctl daemon-reload
else
    echo "    Skipping ka9q-web service configuration (no status address)."
fi

# 7. Restart Services
echo "[+] Restarting Services..."

if [ -n "$INSTANCE_NAME" ]; then
    echo "    Enabling and restarting radiod@$INSTANCE_NAME..."
    sudo systemctl enable "radiod@$INSTANCE_NAME"
    sudo systemctl restart "radiod@$INSTANCE_NAME"
else
    echo "    Skipping radiod start (no instance found)."
fi

if [ -n "$STATUS_ADDR" ]; then
    echo "    Enabling and starting ka9q-web..."
    sudo systemctl enable ka9q-web
    sudo systemctl restart ka9q-web
    echo "=== Installation Complete ==="
    echo "ka9q-web service is active."
else
    echo "=== Installation Partial ==="
    echo "ka9q-web installed but NOT started."
    echo "Please configure radiod, then restart the services."
fi
