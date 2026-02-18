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

The script operates by managing three main components within a target directory:

* **`ka9q-radio`**: The core software defined radio daemon and utilities.
* **`ka9q-web`**: The web interface for controlling and monitoring the radio.
* **`onion`**: A C library for creating web servers, required by `ka9q-web`.

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
