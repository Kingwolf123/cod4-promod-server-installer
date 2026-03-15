# COD4 Promod Server Installer for Windows (COD4X + FastDL)

This repository is a **Call of Duty 4: Modern Warfare / COD4 Promod server installer package for Windows**.

It is designed to help people who are searching for things like:
- how to host a COD4 Promod server on Windows
- how to install a COD4X server for Call of Duty 4
- how to set up FastDL for a COD4 server
- how to run a Promod match server with a shareable `connect` command

The project provides the **installer scripts, startup scripts, FastDL launcher, folder structure, and editable config flow** needed to get a COD4 Promod server running with **COD4X**, **Python FastDL**, and **Windows Terminal**.

This repository does **not** distribute the base game, COD4X binaries for redistribution, or Promod assets. It is the automation layer around your own game and mod files.

## COD4X and Promod Links

If you found this repository while looking for **COD4X** or **Promod** itself, use these official project links:

- **COD4X server project:** [callofduty4x/CoD4x_Server on GitHub](https://github.com/callofduty4x/CoD4x_Server)
- **COD4X forums / project site:** [cod4x.ovh](https://cod4x.ovh)
- **Promod official download page:** [promod.github.io](https://promod.github.io/)
- **Promod source code:** [promod/promod4 on GitHub](https://github.com/promod/promod4)

This package is built to help you use those projects more easily in a practical Windows setup workflow.

## Who This Project Is For

This package is aimed at:
- Windows users who want a practical way to install and run a **COD4 Promod server**
- server hosts who do not want to manually wire together **COD4X**, **PowerShell 7**, **Python**, **FastDL**, and startup arguments
- users who want a beginner-friendly install flow but still want plain-text config files they can edit afterward
- people publishing or sharing a local COD4 server package for friends, scrims, mixes, or match hosting

## What This COD4 Server Installer Does

The installer and startup scripts handle the following:
- require `winget` and PowerShell 7 for the installation flow
- detect and install a usable 64-bit Python 3 runtime for the FastDL HTTP server
- optionally copy base COD4 files from an existing install
- optionally download and install COD4X dedicated server files
- guide you through choosing the Promod mod folder name
- tell you exactly where to copy Promod files for both the game server and FastDL
- validate that the required files exist before finishing
- update `server\start_script\server_args.psd1`
- update the selected mod's `server_match.cfg`
- launch the COD4 match server, FastDL server, and a dedicated connect-command tab in Windows Terminal

## What This Project Does Not Include

This repository does not include:
- base Call of Duty 4 game files
- COD4X server binaries for redistribution
- Promod assets for redistribution
- custom map assets

You must provide the game and mod content yourself.

## Repository Layout

```text
install_server.bat
installation_scripts/
  install_server.ps1
  install_config.psd1
server/
  start_match.bat
  start_script/
    start_services.ps1
    server_args.psd1
    README.txt
  mods/
  main/
  zone/
  usermaps/
http_fast_download_server/
  startup_script.ps1
  start_http_server.bat
  cod4/
BEGINNER_GUIDE.txt
README_PACKAGE.txt
README.md
```

## Main Entry Points

### `install_server.bat`
The main Windows entry point for installation.

It:
- checks for `winget`
- checks for PowerShell 7
- installs or upgrades PowerShell 7 if needed
- runs the PowerShell installer script
- keeps the terminal open at the end so the user can read the result

### `installation_scripts/install_server.ps1`
The main installer logic.

It:
- checks Python availability and can install it automatically
- optionally copies base game files
- optionally installs COD4X server files
- asks for the Promod mod folder name and server settings
- validates required folders and files
- writes updated values into `server_args.psd1` and `server_match.cfg`

### `server/start_match.bat`
The main server startup entry point.

It runs the server startup orchestration script and keeps the terminal open on failure.

### `server/start_script/start_services.ps1`
The startup orchestrator.

It:
- reads launcher settings from `server_args.psd1`
- updates the FastDL base URL in `server_match.cfg`
- finds a usable global IPv6 address
- launches the COD4 match server in its own Windows Terminal tab
- launches the FastDL HTTP server in its own Windows Terminal tab
- opens a separate connect-command tab so the shareable connect line stays visible

### `http_fast_download_server/startup_script.ps1`
The FastDL server launcher.

It:
- locates a usable Python runtime
- starts the built-in Python HTTP server bound to IPv6
- warns the user not to close the FastDL tab or terminal while the server is in use

## Requirements

To use this package as intended, you need:
- Windows
- `winget`
- PowerShell 7
- a usable 64-bit Python 3 runtime
- base COD4 files
- COD4X dedicated server files
- a Promod mod folder with `server_match.cfg`

The package can help install PowerShell 7, Python, and COD4X, but it still depends on you providing the game and mod files.

## How to Set Up a COD4 Promod Server on Windows

1. Run `install_server.bat`.
2. Let the installer handle PowerShell 7 and Python if they are missing.
3. Copy or confirm the base COD4 files.
4. Install or confirm the COD4X server files.
5. Enter the exact Promod mod folder name you want to use.
6. Copy the Promod files into both:
   - `server\mods\<your_mod>\`
   - `http_fast_download_server\cod4\mods\<your_mod>\`
7. Finish the server setup prompts.
8. Run `server\start_match.bat`.
9. Copy the generated `connect [ipv6]:port` command from the connect-command tab and share it with players.

For the more detailed beginner flow, read [BEGINNER_GUIDE.txt](./BEGINNER_GUIDE.txt).

## Promod and FastDL Folder Rules

Your selected mod folder name must match in both locations:
- `server\mods\<your_mod>\`
- `http_fast_download_server\cod4\mods\<your_mod>\`

At minimum, the selected game-server mod folder must contain:
- the Promod files you want to run
- `server_match.cfg`

If you use custom maps, copy them to both locations as well:
- `server\usermaps\<mapname>\`
- `http_fast_download_server\cod4\usermaps\<mapname>\`

## Startup Behavior

When you run `server\start_match.bat`, the launcher is intended to create separate Windows Terminal tabs for:
- the COD4 match server
- the FastDL HTTP server
- the connect command/status tab

Important behavior:
- the FastDL tab must remain open while players are downloading files
- the connect-command tab is meant to remain visible until you copy the command
- the actual server process runs separately from the connect-command tab so its console output does not bury the shareable connection line

## Why This Is Useful for COD4X and Promod Hosts

A typical COD4 Promod setup on Windows often requires several separate manual steps:
- getting PowerShell 7 installed and usable
- installing Python for FastDL
- copying base game files into the right folders
- installing COD4X correctly
- matching the Promod folder name across server and FastDL locations
- keeping the shareable connect command visible while the server is running

This repository is meant to reduce that setup friction and make a repeatable **COD4X + Promod + FastDL** workflow easier to distribute and maintain.

## IPv6 Notes

This package is mainly designed around IPv6.

It can:
- detect a usable global IPv6 address
- write the FastDL URL with that IPv6 address
- print a shareable `connect [ipv6]:port` command

If you want the launcher to prefer a stable DHCPv6 or static IPv6 instead of a temporary/privacy IPv6, edit:
- `server\start_script\server_args.psd1`

Specifically:
- `Launcher -> PreferStableIpv6 = $true`

## Editing and Customization

Normal editable launch values live in:
- `server\start_script\server_args.psd1`

That is where you adjust items such as:
- mod folder selection via `fs_game`
- server port
- RCON password
- startup map
- IPv6 launcher preference

The selected mod's main server config is:
- `server\mods\<your_mod>\server_match.cfg`

## Safety and Scope

These scripts are installation and startup helpers only.
They do not change the runtime performance of your COD4 server beyond starting the required supporting processes and updating config values.

## Troubleshooting

If the installer fails, the most common reasons are:
- `winget` is missing
- PowerShell 7 is missing or outdated
- Python 3 64-bit is unavailable
- base game files were not copied into `server\main` and `server\zone`
- COD4X files were not copied into `server\`
- the Promod folder was not copied into both Promod locations
- `server_match.cfg` is missing from the selected mod folder

If startup fails, check:
- `server\start_script\server_args.psd1`
- the selected mod folder and `server_match.cfg`
- whether you have a usable IPv6 address
- whether the FastDL tab is still running

## Recommended Reading

- [BEGINNER_GUIDE.txt](./BEGINNER_GUIDE.txt)
- [README_PACKAGE.txt](./README_PACKAGE.txt)
- [server/start_script/README.txt](./server/start_script/README.txt)
- [COD4X Server GitHub repository](https://github.com/callofduty4x/CoD4x_Server)
- [Promod official download page](https://promod.github.io/)

## Contributing

If you make improvements to the installer or startup flow, keep the project focused on:
- practical Windows setup
- clear prompts for non-expert users
- editable plain-text config files
- robust startup behavior

## Status

This repository is a script-and-package layer for local distribution and deployment of a COD4 Promod server setup on Windows.
