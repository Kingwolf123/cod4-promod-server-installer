COD4 start script guide
=======================

Files in this folder
--------------------
- start_services.ps1
  Main PowerShell script. It starts the match server, starts the HTTP fast-download server, opens Windows Terminal tabs, and updates sv_wwwBaseURL automatically.

- server_args.psd1
  Editable launch arguments for cod4x18_dedrun.exe.
  If you want to change ports, fs_game, map, gametype, maxclients, or other +set/+exec/+map values, edit this file.

IPv6 preference setting
-----------------------
- The `Launcher` block in `server_args.psd1` controls which IPv6 type is used for:
  - `sv_wwwBaseURL` FastDL rewriting
  - the printed `connect [ipv6]:port` command
- `PreferStableIpv6 = $false`
  Uses a temporary/privacy IPv6.
- `PreferStableIpv6 = $true`
  Prefers a stable DHCPv6 or static IPv6.
- This setting does not rewrite your actual `+set net_ip6` launch arg. It only changes the address-selection logic used by the launcher output and FastDL URL updater.

Temporary IPv6 note
-------------------
- Windows temporary/privacy IPv6 addresses are usually preferred for about 1 day and can remain valid for several more days.
- If you keep the server running for a long time, a temporary FastDL address can eventually age out.
- If you want a more stable address for long-running servers, set `PreferStableIpv6 = $true`.

How to edit server_args.psd1
----------------------------
The MatchServer list is a flat list of command-line tokens.

Example:
    "+set", "net_port", "28962",

This becomes:
    +set net_port 28962

Another example:
    "+map", "mp_crash"

This becomes:
    +map mp_crash

Old BAT format vs new PSD1 format
---------------------------------
Old BAT style:
    cod4x18_dedrun.exe +set fs_game "mods/fps_promod_285" +set net_port 28962 +exec server_match.cfg +map mp_crash

New PSD1 style:
    @(
        "+set", "fs_game", "mods/fps_promod_285",
        "+set", "net_port", "28962",
        "+exec", "server_match.cfg",
        "+map", "mp_crash"
    )

Formatting rules
----------------
1. Keep every token in quotes.
2. Keep the commas.
3. One command can span one line or multiple lines, but each item must stay separated by commas.
4. Do not remove the opening "@(" or closing ")".
5. For values with spaces, keep the whole value in one quoted item.

Example:
    "+set", "r_xassetnum", "material=5000 xmodel=1600 image=4200 fx=600",

Common edits
------------
- Change mod:
    "+set", "fs_game", "mods/fps_promod_285",

- Change server port:
    "+set", "net_port", "28962",

- Change max clients:
    "+set", "sv_maxclients", "24",

- Change config file:
    "+exec", "server_match.cfg",

- Change startup map:
    "+map", "mp_crash"
