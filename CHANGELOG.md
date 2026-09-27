# Changelog

## 0.5.0
- New quest name marker: quests that were not in original Classic get an infinity sign after their name in the Map & Quest Log list and in the objective tracker. It is a small icon in the tint colour by default.
- Marker options: show or hide it, use the icon or a plain text symbol, change the symbol, set the icon height, vertical position and spacing from the name, choose its colour (or follow the tint colour), and move it to the start of the name.
- New optional setting (off by default): recolour the objective lines ("- 0/5 Darkhound Blood") of non-vanilla quests in the quest log list and the tracker. It follows the tint colour unless you choose another. Completed and failed objectives keep their own colours.

## 0.4.0
- New option to add the WoW Forever logo, in the top-right corner above the quest text (quest window and quest log), for quests that were not in original Classic. Off by default.
- "Tint the parchment" and "Add logo" are independent: use either, both or neither.

## 0.3.1
- Works with every Quest Text Contrast setting (Default, Brown, White, Grey, Black).
- On the Black setting the tint is drawn as a flat, deeper teal glow so it is actually visible.

## 0.3.0
- Renamed to **Forever Quest Tint** (`/fqt`).
- Settings panel: enable/disable, tint colour, bottom opacity, top opacity and fade length. Settings are saved between sessions.
- Fixed the teal being hidden behind the Rewards panel when scrolling the quest log.
- Removed debug commands. `/fqt id` prints the current quest ID, for reporting wrongly tinted quests.

## 0.1.0 – 0.2.0
- First versions: teal gradient over the quest text background for quests that were not in original Classic.
