# xraymonitor
This is the first stable release of the Xray Automatic Monitoring script. It continuously checks the server's outbound connection status using a test Xray config. If a disconnection occurs, it executes your custom commands to automatically recover the connection.

Key Features
Automatic, periodic monitoring of the internet connection.

Executes a user-defined custom command on failure (e.g., restarting a service).

Option to automatically reboot the server after a set number of consecutive failures.

Sends notifications via a Telegram bot (for non-Iran servers).

Simple, terminal-based user interface (TUI) for easy installation, uninstallation, and management.

Status dashboard showing service health, last run status, and time until the next check.

Automatically checks for dependencies before installation.

How to Use
Download the script and run it with root access: sudo bash ./script_name.sh

From the menu, choose the Install Monitoring option.

Enter your preferred settings, especially the custom command (LOCAL_COMMAND).
