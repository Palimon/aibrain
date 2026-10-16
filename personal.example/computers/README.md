# Computers

One folder per computer, named after it, for what differs on that computer alone. `bootstrap.sh` adds the folder when you set up a new computer, commits it and pushes it, and on a reinstall you pick the computer from the list of these folders. It reads the folder of the computer it runs on, on every run. `~/.config/aibrain/computer` holds the name. More in aibrain's README, under "Computers".

## config.sh

Settings for this computer, read after `../config.sh`, so a value here wins. `bootstrap.sh` starts it with a line saying what the computer is, which the list on a reinstall shows. Any setting can go here. These are the usual ones:

```sh
TS_SHARE_LAN="192.0.2.0/24"     # this computer shares its LAN with the tailnet
OS_AGENT_DIRS=(/srv/osagent)    # the OS agent keeps its memory on another disk
HYPR_IGNORE_KEY_UNKNOWN=1       # this computer's keyboard sends unsupported key reports
```

## setup.sh

Optional: steps that no setting covers. `bootstrap.sh` runs this at the end of every run, after `../setup.sh` if there is one, with `AIBRAIN`, `PERSONAL`, `COMPUTER` and `BACKUP` set. Make each step converge to what you want, so that a second run changes nothing:

```sh
# Wi-Fi power saving off for this laptop's card
conf=/etc/modprobe.d/iwlwifi-power.conf
line='options iwlwifi power_save=0'
[[ "$(cat "$conf" 2>/dev/null)" == "$line" ]] || echo "$line" | sudo tee "$conf" >/dev/null

# A package only this computer needs
if omarchy-pkg-missing nvtop; then omarchy-pkg-add nvtop; fi
```

If a fix here would help other people too, it can become a setting in aibrain itself, off by default.
