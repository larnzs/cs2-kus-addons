# Google Cloud updater

Google Cloud Compute Engine uses the Linux runtime path. Run this script from the private repository clone on the VM:

```bash
sudo -E bash ./google/update.sh
```

It delegates to `linux/install.sh`: update the repo branch, update managed plugin payloads, update CS2 through SteamCMD, safely overlay the tracked payload, and patch/verify the runtime. It refuses to run while CS2 is active and never launches the server.

Instance metadata secrets are not required for installation or maintenance. Put runtime credentials such as `RCON_PASSWORD` and the GSLT in the Instance's private `instance.env`; only the Instance runner launches CS2.
