# Farm Tally

A lightweight farming session tracker. Automatically counts trade goods (fish, ore, herbs, leather, cloth) as you loot them, tracks vendor trash value, and estimates gold earned per session.

## Features

- **Vendor trash aggregation** — grey items rolled into a single row showing total vendor value
- **Quality tier breakdown** — per-item counts split by crafting quality
- **Session timer** with pause/resume
- **Gold estimation** — total session value and gold per hour (or per minute, click to toggle)
- **Auctionator integration** — uses AH prices when available, vendor prices for grey items
- **Minimap button** — click to toggle widget in HUD
- **Right-click to exclude** — remove unwanted items from the current session
- **Custom tracking** — manually add non-trade-good items via slash command

## Commands

| Command | Description |
|---|---|
| `/fta` | Toggle tracker window |
| `/fta reset` | Reset current session |
| `/fta rate` | Toggle gold/min and gold/hr |
| `/fta add [item]` | Track a custom item (shift-click to insert link) |
| `/fta remove [item]` | Stop tracking a custom item |
| `/fta exclude [item]` | Exclude an item from current session |
| `/fta list` | Show custom tracked and excluded items |
| `/fta debug` | Toggle debug logging |

## Notes

- Pricing features require [Auctionator](https://www.curseforge.com/wow/addons/auctionator). Without it, only vendor trash gold values are shown.
- Trade goods are tracked automatically. Use `/fta add [shift + click on item]` for anything outside that category.
- Excludes and session data reset together. Custom tracked items persist across sessions.
