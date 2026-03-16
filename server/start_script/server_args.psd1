# Editing guide:
# Read server\start_script\README.txt before changing this file.
# start_match.bat only launches the server; the editable launch arguments are here.
# Example: "+set", "net_port", "28962", becomes: +set net_port 28962
# Example: "+map", "mp_crash" becomes: +map mp_crash
@{
    Launcher = @{
        # $false = use a temporary/privacy IPv6 for FastDL and the printed connect command.
        # $true  = prefer a stable DHCPv6/static IPv6 instead.
        PreferStableIpv6 = $false

        # Used only when no usable global IPv6 is available for FastDL.
        # "LanIpv4" = prefer LAN/private IPv4 first, then ULA IPv6.
        # "UlaIpv6" = prefer ULA IPv6 first, then LAN/private IPv4.
        NoGlobalIpv6FastDlPreference = "LanIpv4"
    }

    MatchServer = @(
        "+set", "fs_game", "mods/fps_promod_285",
        "+set", "dedicated", "2",
        "+set", "net_ip6", "::",
        "+set", "net_ip", "0.0.0.0",
        "+set", "net_port", "28962",
        "+set", "sv_maxclients", "24",
        "+set", "r_xassetnum", "material=5000 xmodel=1600 image=4200 fx=600",
        "+set", "g_friendlyPlayerCanBlock", "1",
        "+set", "sv_punkbuster", "1",
        "+set", "set", "g_logsync", "2",
        "+set", "g_gametype", "sd",
        "+set", "developer", "0",
        "+set", "rcon_password", "rcon12345_change",
        "+set", "developer_script", "0",
        "+exec", "server_match.cfg",
        "+map", "mp_crash"
    )
}
