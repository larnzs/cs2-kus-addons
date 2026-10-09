# Archived Windows path collision: MatchZy Portuguese locale

The KUS payload originally contained two files in the disabled MatchZy plugin folder whose names differed only by case:

- `server/game/csgo/addons/counterstrikesharp/plugins/disabled/MatchZy/lang/pt-PT.json` (kept in the runtime tree)
- `server/game/csgo/addons/counterstrikesharp/plugins/disabled/MatchZy/lang/pt-pt.json` (archived here)

Windows filesystems are case-insensitive, so Git could not check out both paths independently. The lower-case version contained fewer translation entries and was archived here to keep its contents without breaking Windows Git operations. MatchZy is under CounterStrikeSharp's disabled plugin directory.
