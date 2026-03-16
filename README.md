# COD4 Promod Server Installer for Windows (COD4X + FastDL)
# Setup a promod server in 2 minutes.

## How to use ( quick ): 

- Download the cod4_promod_server.zip from the latest release 
- run install server
- follow the interactive installation 
- Go to server/start_match to start.
- Thats it. For Further details read instructions in Beginner_Guide.txt and below. Although all steps are covered in the interative install_server.bat process. You shoudnt need anything else to get started.  

This repository is a script-and-package layer for local distribution and deployment of a COD4 Promod server setup on Windows.
The project provides the **installer scripts, startup scripts, FastDL launcher, folder structure, and editable config flow** needed to get a COD4 Promod server running with **COD4X**, **Python FastDL**, and **Windows Terminal**.

It is designed to help people who are searching for things like:

- how to host a COD4 Promod /match server on Windows
- how to install a COD4X server for Call of Duty 4
- how to set up FastDL for a COD4 server
- Meant to be extensible in its design for anyone wanting to do anything other, adding parameters etc. Designed to be general purpose, standard, modular and extensible in terms of script design. Can host any other mod / game mode just as well 

This repository does **not** distribute the base game, COD4X binaries for redistribution, or Promod assets. It is a automation layer.

 .

## Who This Project Is For

This package is aimed at:

- Windows users beginner users who want a practical and fast way to install and run a fully fledged **COD4 Promod server** for scrims, 1v1s, local LANs. For players who wish they had a cod4 promod server they could fire up to play with friends occasionally
- , but dont know how and just dont want to get into. Your just a player who wants to play, i get you.
- server hosts who do not want to manually wire together **COD4X**, **PowerShell 7**, **Python**, **FastDL**, and startup arguments. A complicated affair!
A typical COD4 Promod setup on Windows often requires several separate manual steps that can take hours for a first timer to understand and execute. 

## What This COD4 Server Installer Does

The installer and startup scripts handle the following:

- require `winget` and PowerShell 7 for the installation. Install them if not detected
- detect and install a usable 64-bit Python 3 runtime for the FastDL HTTP server
- optionally copy base COD4 files from an existing install into the /server directory
- optionally download and install COD4X dedicated server files from the official cod4x automatically
- tell you exactly to copy Promod files for both the game server and FastDL .
- validates that the required files exist before finishing
- update `server\start_script\server_args.psd1` . This replaces the traditional command line arguments such as +map mp_crash +set fs_game etc for the server.
- update the selected mod's `server_match.cfg`
- launch the COD4 match server, FastDL server, and a fully compiled connect command to share with a single click.

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

## What This Project Does Not Include

This repository does not include:

- base Call of Duty 4 game files
- COD4X server binaries for redistribution
- Promod assets for redistribution
- custom map assets

You must provide the game and mod content yourself.

## Description file contents

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

The main server startup entry point. This is where u start your game server . It opens everything with a single click needed for the server to get running. 

It runs the server startup orchestration script 
For details optionally  read the startup Behaviour Section below.

## Startup Behavior

When you run `server\start_match.bat`, the launcher is intended to create separate Windows Terminal tabs for:

- the COD4 match server
- the FastDL HTTP server
- the connect command/status tab

Important behavior:

- the FastDL tab must remain open while players are downloading files
- the connect-command tab is meant to remain visible for ease of use of copy pasting the complete connect ip command to your friends

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
- starts the built-in Python HTTP server bound to IPv6. If no GUA IPv6 is detected, it falls back to dual-stack and rewrites `sv_wwwBaseURL` using the no-GUA FastDL preference from `server_args.psd1` (`LanIpv4` first by default, or `UlaIpv6` if you choose it).

## Prerequisite and Requirements List

You need the following prerequisites:

- Windows 10/11
- winget
- PowerShell 7
- a usable 64-bit Python 3 runtime ( eg 3.14, 3.10 etc)

  Cod4 related:
- base COD4 files
- COD4X dedicated server files
- a Promod mod   ( server_match.cfg is already provided and should be used for default promod match servers, but feel free to edit or change anything or add ur own)

The package automatically installs everything for you in the installer, except for the promod folder or any mod, which u need to manually add. 

## Guide on using install_server.bat

Although instructions already mentioned in the installer and beginner guide , repeating here.

1. Run `install_server.bat`.
2. Let the installer handle PowerShell 7 and Python if they are missing. install these manually if in some cases the installer fails.
3. Copy or confirm the base COD4 files.
4. Install or confirm the COD4X server files.
5. Enter the exact Promod mod folder name you want to use.
6. Copy the Promod files into both:
   - `server\mods\<your_mod>\`
   - `http_fast_download_server\cod4\mods\<your_mod>\`
7. Finish the server setup prompts.
8. Run `server\start_match.bat`.
9. Copy the generated `connect [ipv6]:port` command from the connect-command tab and share it with players.

For more detailed and complete guide, read [BEGINNER_GUIDE.txt](./BEGINNER_GUIDE.txt).

## FastDL Folder Rules

Your selected mod folder name must match in both locations:

- `server\mods\<your_mod>\`
- `http_fast_download_server\cod4\mods\<your_mod>\`

If you use custom maps, copy them to both locations as well:

- `server\usermaps\<mapname>\`
- `http_fast_download_server\cod4\usermaps\<mapname>\`

## IPv6 Notes

This package is mainly designed around IPv6 .Although still works with ipv4.

It can:

- detect a usable global IPv6 address
- write the FastDL URL with that IPv6 address
- print a shareable `connect [ipv6]:port` command

If you want the launcher to prefer a stable DHCPv6 or static IPv6 instead of a temporary/privacy IPv6, edit:

- `server\start_script\server_args.psd1`
Read advanced note in beginner_guide ( Yes i get the irony).

Specifically:
- `Launcher -> PreferStableIpv6 = $true`

Please ensure your ipv6 firewall allows the ports or is disabled.

## Editing and Customization

As mentioned before, the scripts are extensible and modular. Feel free to extend or add commands and stuff. Some basic ways are mentioned below.

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

These scripts are installation and startup helpers/automations only.
They do not change the runtime performance of your COD4 server or any other application.

## Troubleshooting

If the installer fails, the most common reasons are:

- `winget` is missing
- PowerShell 7 is missing or outdated
- Python 3 64-bit is unavailable
- base game files were not copied into `server\main` and `server\zone`
- COD4X files were not copied into `server\` appropriately
- the Promod folder was not copied into both Promod locations
- `server_match.cfg` is missing from the selected mod folder

If startup fails, check:

- `server\start_script\server_args.psd1`
- the selected mod folder and `server_match.cfg`
- whether you have a usable IPv6 address / properly setup ipv4
- whether the FastDL tab is still running

## Additional Readings for the Curious 

- [COD4X Server GitHub repository](https://github.com/callofduty4x/CoD4x_Server)
- [Promod official download page](https://promod.github.io/) 

## Contributing

If you make improvements to the installer or startup flow or find any bugs, keep the contributions focused on:

- practical Windows setup leading to simplicity.
- focused on design around non technical users

## COD4X and Promod Links

If you found this repository while looking for **COD4X** or **Promod** itself, use these official project links for downloading or reference:

- **COD4X server project:** [callofduty4x/CoD4x_Server on GitHub](https://github.com/callofduty4x/CoD4x_Server)
- **COD4X forums / project site:** [cod4x.ovh](https://cod4x.ovh)
- **Promod official download page:** [promod.github.io](https://promod.github.io/)
- **Promod source code:** [promod/promod4 on GitHub](https://github.com/promod/promod4)
