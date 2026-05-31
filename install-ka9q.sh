#!/bin/bash
set -e

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
PIN_COMMIT=""
TARGET_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pin-commit)
            PIN_COMMIT="$2"
            shift 2
            ;;
        --pin-commit=*)
            PIN_COMMIT="${1#*=}"
            shift
            ;;
        --no-pin)
            PIN_COMMIT="HEAD"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--pin-commit HASH | --no-pin] [TARGET_DIRECTORY]"
            echo ""
            echo "Options:"
            echo "  --pin-commit HASH  Checkout ka9q-radio at a specific commit"
            echo "  --no-pin           Build from ka9q-radio HEAD (skip pin detection)"
            echo ""
            echo "If --pin-commit is not given, the script tries to read the pin from:"
            echo "  1. Installed ka9q-python package (ka9q.compat.KA9Q_RADIO_COMMIT)"
            echo "  2. Sibling ka9q-python/ka9q_radio_compat file"
            echo "  3. Falls back to HEAD if neither is available"
            exit 0
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

TARGET_DIR="${TARGET_DIR:-$PWD}"

echo "=== ka9q-radio & ka9q-web Installer ==="
echo "Target Directory: $TARGET_DIR"

# Verify sudo access upfront
echo "This installer requires administrative privileges."
if ! sudo -v; then
    echo "Error: Need sudo privileges to run this installer."
    exit 1
fi
# Keep-alive: update existing sudo time stamp until the script has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

if [ ! -d "$TARGET_DIR" ]; then
    echo "Creating target directory: $TARGET_DIR"
    mkdir -p "$TARGET_DIR"
fi

RADIO_DIR="$TARGET_DIR/ka9q-radio"
WEB_DIR="$TARGET_DIR/ka9q-web"
ONION_DIR="$TARGET_DIR/onion"
LIBFOBOS_DIR="$TARGET_DIR/libfobos"
HYDRASDR_DIR="$TARGET_DIR/hydrasdr-host"

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
    git -C "$RADIO_DIR" fetch origin
    # Ensure we're on a branch before pulling (re-runs leave detached HEAD after commit pin).
    git -C "$RADIO_DIR" checkout main 2>/dev/null || git -C "$RADIO_DIR" checkout master 2>/dev/null || true
    git -C "$RADIO_DIR" pull
else
    echo "    Cloning ka9q-radio..."
    git clone https://github.com/ka9q/ka9q-radio.git "$RADIO_DIR"
fi

# --- Resolve ka9q-radio pin commit ---
if [ -z "$PIN_COMMIT" ]; then
    # Try 1: installed ka9q-python package
    PIN_COMMIT=$(python3 -c "from ka9q.compat import KA9Q_RADIO_COMMIT; print(KA9Q_RADIO_COMMIT)" 2>/dev/null || true)

    # Try 2: sibling ka9q-python checkout
    if [ -z "$PIN_COMMIT" ] || [ "$PIN_COMMIT" = "unknown" ]; then
        COMPAT_FILE="$TARGET_DIR/ka9q-python/ka9q_radio_compat"
        if [ -f "$COMPAT_FILE" ]; then
            PIN_COMMIT=$(grep -v '^#' "$COMPAT_FILE" | grep -v '^$' | head -n1)
        fi
    fi
fi

if [ -n "$PIN_COMMIT" ] && [ "$PIN_COMMIT" != "HEAD" ] && [ "$PIN_COMMIT" != "unknown" ]; then
    echo "    Pinning ka9q-radio to commit: ${PIN_COMMIT:0:12}"
    if git -C "$RADIO_DIR" cat-file -t "$PIN_COMMIT" >/dev/null 2>&1; then
        git -C "$RADIO_DIR" checkout "$PIN_COMMIT"
    else
        echo "    WARNING: Pin commit $PIN_COMMIT not found in ka9q-radio repo."
        echo "             Building from HEAD instead."
    fi
else
    echo "    Building ka9q-radio from HEAD (no pin detected)."
fi

# ka9q-web
if [ -d "$WEB_DIR" ]; then
    echo "    Updating ka9q-web..."
    # Ensure we're on a branch before pulling — a previous run (or manual
    # operator checkout) can leave the repo in detached HEAD, which makes
    # `git pull` fail with "You are not currently on a branch" under set -e.
    git -C "$WEB_DIR" checkout main 2>/dev/null || git -C "$WEB_DIR" checkout master 2>/dev/null || true
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

# libfobos (RigExpert Fobos SDR API — ka9q-radio fobos.so plugin links -lfobos)
if [ -d "$LIBFOBOS_DIR" ]; then
    echo "    Updating libfobos..."
    git -C "$LIBFOBOS_DIR" checkout master 2>/dev/null || git -C "$LIBFOBOS_DIR" checkout main 2>/dev/null || true
    git -C "$LIBFOBOS_DIR" pull
else
    echo "    Cloning libfobos..."
    git clone https://github.com/rigexpert/libfobos.git "$LIBFOBOS_DIR"
fi

# hydrasdr-host (HydraSDR host software — ka9q-radio hydrasdr.so plugin links -lhydrasdr)
if [ -d "$HYDRASDR_DIR" ]; then
    echo "    Updating hydrasdr-host..."
    git -C "$HYDRASDR_DIR" checkout main 2>/dev/null || git -C "$HYDRASDR_DIR" checkout master 2>/dev/null || true
    git -C "$HYDRASDR_DIR" pull
else
    echo "    Cloning hydrasdr-host..."
    git clone https://github.com/hydrasdr/hydrasdr-host.git "$HYDRASDR_DIR"
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

# 2a. Build and Install libfobos
echo "[+] Building and Installing libfobos..."
cd "$LIBFOBOS_DIR"
mkdir -p build
cd build
cmake .. > cmake_output.txt 2>&1 || { echo "Error: libfobos cmake failed."; cat cmake_output.txt; exit 1; }
make -j$(nproc)
sudo make install
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo ldconfig

# 2b. Build and Install hydrasdr-host (libhydrasdr + tools)
echo "[+] Building and Installing hydrasdr-host..."
cd "$HYDRASDR_DIR"
mkdir -p build
cd build
cmake -DINSTALL_UDEV_RULES=ON .. > cmake_output.txt 2>&1 || { echo "Error: hydrasdr-host cmake failed."; cat cmake_output.txt; exit 1; }
make -j$(nproc)
sudo make install
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo ldconfig

# 3. Build and Install ka9q-radio
# MOVED UP: Must be installed before we can check /etc/radio config
echo "[+] Building and Installing ka9q-radio..."

# Create the `radio` user/group that ka9q-radio's systemd units run as
# and that its Makefile chowns paths to.  Upstream's aux/Makefile (line 81)
# does `chown radio:radio` but never creates the user — that's handled
# only by debian/preinst, which native (non-deb) installs never invoke.
# Without this, radiod@*.service silently fails ExecStart user lookup.
if ! getent passwd radio >/dev/null 2>&1; then
    echo "    Creating system user/group: radio"
    sudo useradd --system --user-group --no-create-home \
                 --home-dir /var/lib/ka9q-radio \
                 --shell /usr/sbin/nologin radio
fi

cd "$RADIO_DIR"
make -j$(nproc)
sudo make install

# `make install` writes /usr/lib/tmpfiles.d/ka9q-radio-common.tmpfiles which
# declares /etc/radio, /var/lib/ka9q-radio, /usr/share/ka9q-radio — but only
# debian/postinst invokes systemd-tmpfiles --create.  Trigger it here so
# native installs create those dirs too; without them, radiod has no config
# to read and writes no state.
sudo systemd-tmpfiles --create

# 4. Detect Configuration
echo "[+] Detecting Configuration..."
RADIOD_WAS_RUNNING=0
# Try to find running radiod instance first
RUNNING_INSTANCE=$(systemctl list-units --type=service --state=running --no-legend "radiod@*" | cut -d' ' -f1 | head -n1)

if [ -n "$RUNNING_INSTANCE" ]; then
    RADIOD_WAS_RUNNING=1
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
        read -p "Press Enter to continue installation (service start will fail) or Ctrl+C to abort..." || true
    else
        INSTANCE_NAME=$(basename "$CONFIG_FILE" | sed -E 's/radiod@(.*)\.conf/\1/')
        echo "    Found configuration file for instance: $INSTANCE_NAME (currently stopped)"
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

# Check if ka9q-web was running
WEB_WAS_RUNNING=0
if systemctl is-active --quiet ka9q-web 2>/dev/null; then
    WEB_WAS_RUNNING=1
    echo "    ka9q-web service is currently running."
else
    echo "    ka9q-web service is currently stopped (or not installed)."
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
    KA9Q_WEB_SERVICE_SRC="$WEB_DIR/ka9q-web.service"
    # Use mktemp so re-runs don't trip over a prior run's leftover at a
    # fixed path — `cp` to /tmp/ka9q-web.service fails with "Permission
    # denied" if a previous successful run left that file owned by root
    # (because the sudo cp on the next line copied it to systemd as root)
    # and the current run is unprivileged.  mktemp is unique-per-run and
    # owned by the invoking user, so this cp always succeeds.
    TEMP_SERVICE_FILE=$(mktemp -t ka9q-web.service.XXXXXX)
    trap 'rm -f "$TEMP_SERVICE_FILE"' EXIT

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

# 7. Generate FFTW Wisdom
echo "[+] Generating FFTW Wisdom..."

KA9Q_RADIO_WISDOM_FILE_PATH="/var/lib/ka9q-radio/wisdom"
FFTW_SYSTEM_WISDOM_FILE_PATH="/etc/fftw/wisdomf"
TMP_WISDOM_FILE_PATH="/tmp/wisdom"

# The slow 129Msps plan is excluded by default
FFT_RATES="rof1620000 cob162000 cob81000 cob40500 cob32400 cob16200 cob9600 cob8100 cob6930 cob4860 cob4800 cob3240 cob3200 cob1920 cob1620 cob1600 cob1200 cob960 cob810 cob800 cob600 cob480 cob405 cob400 cob320 cob300 cob205 cob200 cob160 cob85 cob45 cob15"

# Provide existing wisdom to fftwf-wisdom to speed things up if it exists
REF_WISDOM_ARG=""
if [ -f "$KA9Q_RADIO_WISDOM_FILE_PATH" ]; then
    REF_WISDOM_ARG="-w $KA9Q_RADIO_WISDOM_FILE_PATH"
fi

echo "    Running fftwf-wisdom to optimize FFTs (this may take a few moments)..."
fftwf-wisdom -v -T 1 $REF_WISDOM_ARG -o "$TMP_WISDOM_FILE_PATH" $FFT_RATES > /dev/null 2>&1

echo "    Installing new wisdom files..."
for WISDOM_FILE in "$KA9Q_RADIO_WISDOM_FILE_PATH" "$FFTW_SYSTEM_WISDOM_FILE_PATH"; do
    # Create directory if needed
    sudo mkdir -p "$(dirname "$WISDOM_FILE")"
    
    CURRENT_SIZE=0
    if [ -f "$WISDOM_FILE" ]; then
        CURRENT_SIZE=$(stat -c %s "$WISDOM_FILE" 2>/dev/null || echo 0)
    fi
    
    NEW_SIZE=0
    if [ -f "$TMP_WISDOM_FILE_PATH" ]; then
        NEW_SIZE=$(stat -c %s "$TMP_WISDOM_FILE_PATH" 2>/dev/null || echo 0)
    fi
    
    if [ "$NEW_SIZE" -gt 0 ]; then
        if [ "$NEW_SIZE" -gt "$CURRENT_SIZE" ] || [ ! -f "$WISDOM_FILE" ]; then
            echo "    Installing updated wisdom in $WISDOM_FILE"
            sudo cp -p "$TMP_WISDOM_FILE_PATH" "$WISDOM_FILE"
            sudo chmod 664 "$WISDOM_FILE"
            # Attempt to set ownership to match directory if it exists
            DIR_OWNER=$(stat -c %U:%G "$(dirname "$WISDOM_FILE")" 2>/dev/null || echo "root:root")
            sudo chown "$DIR_OWNER" "$WISDOM_FILE"
        else
            echo "    Skipping update for $WISDOM_FILE (existing is larger or equal)"
        fi
    fi
done

# Cleanup
rm -f "$TMP_WISDOM_FILE_PATH"

# 8. Restart Services
echo "[+] Restarting Services..."

# Helper function to conditional start services
prompt_start_service() {
    local SERVICE_NAME="$1"
    local WAS_RUNNING="$2"
    
    sudo systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    
    if [ "$WAS_RUNNING" -eq 1 ]; then
        echo "    Restarting previously running service: $SERVICE_NAME..."
        sudo systemctl restart "$SERVICE_NAME"
    else
        echo "    Service $SERVICE_NAME was not running before the update."
        read -p "    Do you want to start $SERVICE_NAME now? [y/N]: " START_RESPONSE || true
        if [[ "$START_RESPONSE" =~ ^[Yy]$ ]]; then
            echo "    Starting $SERVICE_NAME..."
            sudo systemctl start "$SERVICE_NAME"
        else
            echo "    Leaving $SERVICE_NAME stopped."
        fi
    fi
}

if [ -n "$INSTANCE_NAME" ]; then
    prompt_start_service "radiod@$INSTANCE_NAME" "$RADIOD_WAS_RUNNING"
else
    echo "    Skipping radiod start (no instance found)."
fi

if [ -n "$STATUS_ADDR" ]; then
    prompt_start_service "ka9q-web" "$WEB_WAS_RUNNING"
    echo "=== Installation Complete ==="
    if systemctl is-active --quiet ka9q-web 2>/dev/null; then
        echo "ka9q-web service is active."
    else
        echo "ka9q-web service is installed but currently stopped."
    fi
else
    echo "=== Installation Partial ==="
    echo "ka9q-web installed but NOT started."
    echo "Please configure radiod, then restart the services."
fi
