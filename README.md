# ka9q-update

A utility to install and update ka9q-radio and ka9q-web.

## The Script: `install-ka9q.sh`

This bash script automates the process of installing, updating, and configuring the `ka9q-radio` and `ka9q-web` software stack, including the necessary dependencies and the Onion framework.

### Purpose

The primary goals of this script are:

1. **Dependency Management**: Installs all required system packages for building and running the radio software, as well as the Onion web framework.
2. **Repository Management**: Clones or updates the source code repositories for `ka9q-radio`, `ka9q-web`, and `onion`.
3. **Build Automation**: Compiles and installs the software from source.
4. **Configuration**: Automatically detects the active radio configuration and updates the `ka9q-web` service to monitor the correct status stream.
5. **Service Management**: Installs and restarts the necessary systemd services to ensure everything is running.

### Organization

The script operates by managing these components within a target directory:

* **`ka9q-radio`**: The core software defined radio daemon and utilities.
* **`ka9q-web`**: The web interface for controlling and monitoring the radio.
* **`onion`**: A C library for creating web servers, required by `ka9q-web`.
* **`libfobos`**: RigExpert Fobos SDR host library. Required because
  `ka9q-radio` builds the `fobos.so` device plugin by default
  (`ENABLE_FOBOS=1`) and links it against `-lfobos`. No Debian package
  exists, so the source is cloned and built from
  `github.com/rigexpert/libfobos`.
* **`hydrasdr-host`**: HydraSDR host software (provides `libhydrasdr`).
  Required because `ka9q-radio` builds the `hydrasdr.so` device plugin
  by default (`ENABLE_HYDRASDR=1`) and links it against `-lhydrasdr`.
  No Debian package exists, so the source is cloned and built from
  `github.com/hydrasdr/hydrasdr-host`.

It attempts to be "smart" about existing installations:

* If directories exist, it updates them via `git pull`.
* If services are already running, it restarts them to apply updates.
* It looks for active `radiod` configurations to properly link the web interface to the radio backend.

### Usage

Run the script from the command line, optionally specifying a target directory where the source code repositories should reside.

```bash
./install-ka9q.sh [TARGET_DIRECTORY]
```

**Arguments:**

* `TARGET_DIRECTORY` (Optional): The directory where the `ka9q-radio`, `ka9q-web`, and `onion` repositories will be cloned or found.
  * If not specified, it defaults to the **current working directory**.

**Examples:**

1. **Install in the current directory:**

    ```bash
    ./install-ka9q.sh
    ```

2. **Install in a specific `git` folder:**

    ```bash
    ./install-ka9q.sh ~/git
    ```

    This will result in repositories at `~/git/ka9q-radio`, `~/git/ka9q-web`, and `~/git/onion`.

**Requirements:**

* The script requires `sudo` privileges to install packages and services. You may be prompted for your password.
* An active internet connection is required to fetch packages and clone repositories.

### ka9q-python Compatibility Pin

The installer can build ka9q-radio at a **specific commit** validated by `ka9q-python`, ensuring protocol compatibility between `radiod` and Python clients.

**How it works:** When run without `--no-pin`, the script automatically resolves the pinned commit:

1. **`--pin-commit HASH`** — Explicit override (highest priority)
2. **Installed `ka9q-python`** — Reads `ka9q.compat.KA9Q_RADIO_COMMIT` via Python
3. **Sibling checkout** — Reads `TARGET_DIR/ka9q-python/ka9q_radio_compat`
4. **Falls back to HEAD** — If no pin is found

**Examples:**

```bash
# Auto-detect pin from installed ka9q-python or sibling checkout
./install-ka9q.sh ~/git

# Explicit pin
./install-ka9q.sh --pin-commit 6b0fec7dae82bf5f4d80cad88ec343453d6e6950 ~/git

# Ignore pin, build from latest HEAD
./install-ka9q.sh --no-pin ~/git
```

**Updating the pin:** When `ka9q-python` is updated (via `pip install --upgrade ka9q-python` or a new checkout), the pin automatically reflects the new validated commit. Simply re-run the installer to rebuild `radiod` at the matching version.

## Configuration Template

A template configuration file, `radiod@template.conf`, is included in this repository.

### Template Usage

1. Copy the template to the radio configuration directory:

    ```bash
    sudo cp radiod@template.conf /etc/radio/radiod@my-instance-name.conf
    ```

    *Replace `my-instance-name` with your desired instance identifier (e.g., `hf`, `vhf`).*

2. Edit the file and replace the placeholders with your specific configuration:
    * `YOUR_STATUS_HOST.local`: The multicast DNS name for status updates.
    * `YOUR_INTERFACE_NAME`: The network interface to use (e.g., `eth0`).
    * `YOUR_CALLSIGN`: Your amateur radio callsign.
    * `YOUR_GRID`: Your Maidenhead grid locator.
    * `YOUR_ANTENNA`: A description of your antenna.
