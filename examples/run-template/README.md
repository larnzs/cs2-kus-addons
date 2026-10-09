# CS2 instance runner template

This folder is a reusable example of the Windows runner/supervisor pair:

- \`run.bat\` reads settings from \`instance.ini\`, syncs the instance's custom \`cfg/\` and \`addons/\` files, starts CS2, and restarts the instance 5 seconds after the game process exits.
- \`run.vbs\` launches \`run.bat\` hidden and supervises it, matching the style of the supplied \`27100_run.bat\` and \`27100.vbs\`.
- \`instance.example.ini\` contains the editable settings template.

## Set it up

1. Copy this folder for each server instance, for example \`instances/aim/\`.
2. Copy \`instance.example.ini\` to \`instance.ini\`.
3. Edit \`SERVER_DIR\` so it points to the KUS server installation directory containing \`game\\bin\\win64\\cs2.exe\`.
4. Edit \`IP\`, \`PORT\`, \`CUSTOM_FOLDER\`, \`MAP\`, and \`EXEC\` for the specific instance.
5. Fill in \`STEAM_ACCOUNT\` and a strong \`RCON_PASSWORD\` in the local \`instance.ini\` only. Set \`API_KEY\` only if your setup needs it.
6. Start \`run.vbs\` when the installation is ready.

The folder's \`.gitignore\` excludes \`instance.ini\` so local credentials and per-machine settings are not committed. Leave \`instance.example.ini\` safe to share.

## Paths and behavior

- \`SERVER_DIR\` may be an absolute path (drive or UNC) or a path relative to this folder.
- \`CUSTOM_FOLDER\` may be absolute or relative to this folder. The runner merges only its \`cfg/\` and \`addons/\` children into \`SERVER_DIR\\game\\csgo\`; it does not delete other files.
- \`BIND_IP\` controls the local listen address, defaulting to \`0.0.0.0\`. \`IP\` is passed to \`+net_public_adr\` as the advertised public address.
- \`WORKSHOP_COLLECTION\` is optional and is omitted from the launch arguments when blank.
- \`API_KEY\` and \`STEAM_ACCOUNT\` are only added to the launch arguments when non-empty.
- The runner does not run SteamCMD or update CS2. The initial game install and the later update-checker/VBS update handoff are handled separately by the main repository workflow.
- The VBS supervisor is designed to run continuously. Stop it to stop automatic restarts.
