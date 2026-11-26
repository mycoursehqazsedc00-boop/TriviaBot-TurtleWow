# TriviaBot-TurtleWoW (v1.4 — Unified Warcraft & Turtle WoW Edition)

> A lightweight, single-folder in-game chat trivia host for Vanilla WoW 1.12 and Turtle WoW featuring **1,299 curated questions** (Turtle WoW custom lore, geography, mechanics, stats & notable items + strictly pre-TBC `<= Dec 2006` Warcraft I–III & Vanilla WoW lore and geography), A/B/C/D multiple choice, fuzzy answer matching, Win Streaks, Round Mode, Auto-Pause in Combat, AFK Auto-Stop, and a Live Host Standings panel.

## Client Mods Used

| Mod | Purpose in this addon | Required? |
|---|---|---|
| **UnitXP SP3** | Optional taskbar icon flash notification (`UnitXP("notify", "taskbarIcon")`) when a player answers a question while `/trivia notify` is enabled | Optional |

*(Runs in strict Vanilla-Safe Lua 5.0 mode and works completely without any client DLL mods.)*

## Features

- **Unified Single-Folder Question Pack (`WarcraftQuestions.lua` — 1,299 Questions):**
  - Stored as tab-delimited packed strings (`217 KB`, zero sub-tables, zero duplicate array copies) with **100% curated A/B/C/D choices** (1,299 / 1,299).
  - Covers **Turtle WoW** custom zones & lore (Northwind, Balor, Grim Reaches, Dun Kithas, Gilneas, Lapidis & Gillijim's Isles, Tel'Abim, Alah'Thalas, Blackstone Island, Emerald Sanctum, Tower of Karazhan, Dragonmaw Retreat, Stormwrought Ruins, Crescent Grove, Hateforge Quarry, Stormwind Vault, Black Morass), **Turtle WoW game mechanics, stats & notable items** (Patch 1.17.2+ Weapon Skill rework, Vampirism, Haste, Armor Penetration, Tier 3.5, Facetted Crystal Scope, Challenge Modes, iconic Vanilla/Turtle items), and **pre-TBC (`<= Dec 2006`) Warcraft I–III & Vanilla WoW lore and Azeroth geography**.
  - **100% curated A/B/C/D choices** (1,299 / 1,299) stored as tab-delimited packed strings (zero sub-tables, zero duplicate array copies).
- **Graphical Settings Menu & Live Host Standings (`/trivia`):**
  - Embedded right-side **Live Standings** panel showing Top 10 players, active win streaks, Speed Record, Best Streak, Round progress, and AFK unanswered counter without spamming chat.
  - One-click **Chat Channel** presets (`SAY`, `PARTY`, `RAID`, `GUILD`) + custom channel box.
  - Sliders for **Time per Question** (`10`–`180`s), **Time Warning** (`0`–`60`s), **Delay** (`3`–`30`s), and **Leaderboard Frequency** (`0`–`20`).
  - Compact steppers for **Round Limit** (`0`–`50` Qs), **Target Score** (`0`–`30` pts), and **AFK Auto-Stop** (`0`–`10` unanswered Qs).
- **Win Streak & Round Mode:**
  - Announces consecutive correct streaks (`3x`, `5x`, `10x+`) and streak-break callouts, plus Best Streak in standings.
  - Fixed-length rounds (`Q (1/10): ...`) or first-to-N-points races that automatically announce final standings and stop cleanly.
- **Auto-Pause in Combat & AFK Auto-Stop:**
  - Automatically freezes the active question timer on `PLAYER_REGEN_DISABLED` and resumes with remaining seconds on `PLAYER_REGEN_ENABLED` (plus manual `/trivia pause` and `/trivia resume`).
  - Automatically stops after N consecutive unanswered questions to prevent channel spam when AFK.
- **Moveable On-Screen Control Button (`TriviaBotToggleButton`):**
  - **Left-Click:** Start / Stop trivia (shows live countdown, `PAUSED`, or `COMBAT` status).
  - **Right-Click:** Open / close `/trivia` Settings & Live Standings.
  - **Shift + Right-Click:** Skip current question while running.
  - **Drag:** Move anywhere on screen (persisted in `TRIVIA_CONFIG`).
- **Smart Fuzzy ("Likely") Answer Matching & `WoWTranslate` Compatibility:**
  - Accepts A/B/C/D letters (with 3s wrong-letter anti-spam cooldown) or typed answers with case/punctuation/article stripping, number-word conversion, core keyword extraction, and zero-alloc Levenshtein typo tolerance.
  - Uses `WoWTranslate_SendRaw` when present and strips `[...WoWTranslate...]` prefixes on incoming answers.

## What Was Added / Improved

- **v1.4 (Unified Warcraft & Turtle WoW Expansion):**
  - Removed `Geography` and `Normal` non-Warcraft packs and merged `Turtle` + `WoW` into a single packed file (`WarcraftQuestions.lua`) inside `TriviaBot-TurtleWow`.
  - Added **130 new curated questions** covering Turtle WoW 1.17.2+/1.18 mechanics, stats, and iconic items, Turtle WoW custom lore & geography, and pre-TBC (`<= Dec 2006`) Warcraft lore & Azeroth geography (`1,299` unique questions total).
  - Simplified the Settings Menu (`655x500`) by removing the obsolete multi-pack selector grid and automatically migrating any saved legacy `TRIVIA_QLIST` to `"warcraft"`.
- **v1.3 (Ultra-Low-Memory Architecture & Host QoL):**
  - Converted question data to `LoadOnDemand: 1` packed tab-delimited strings (zero sub-tables, zero duplicate copies, 0 KB question data at login).
  - Added zero-CPU idle mode (hidden `Trivia` frame detaches `OnUpdate` and unregisters `CHAT_MSG_*` when stopped; single-channel event registration while running) and hoisted reusable buffers.
  - Added Win Streak tracking, Round Mode (`/trivia round`, `/trivia target`), Auto-Pause in Combat (`/trivia combat` + `/trivia pause`/`resume`), AFK Auto-Stop (`/trivia afk`), embedded Live Standings panel, and `/trivia mem`.
  - Fixed Vanilla-unsupported `EditBox:HasFocus()`, idle `"score"` auto-whispers, frozen Options timer when toggle button is hidden, premature channel leave on protected keywords, and `/trivia shuffle` mid-question state.

## Usage

- `/trivia` | `/trivia menu` — Open Settings & Live Standings.
- `/trivia start` | `/trivia stop` | `/trivia pause` | `/trivia resume` | `/trivia toggle` — Control TriviaBot.
- `/trivia round <0-50>` — Set fixed question limit per round (`0` = endless).
- `/trivia target <0-30>` — Set first-to-N-points win target (`0` = off).
- `/trivia afk <0-10>` — Set consecutive unanswered questions before auto-stopping (`0` = off, default `5`).
- `/trivia combat [on|off]` — Toggle auto-pause when entering combat (default `on`).
- `/trivia timer <10-180>` | `/trivia warn <0-60>` | `/trivia delay <3-30>` | `/trivia report <0-20>` — Configure timers and report frequency.
- `/trivia channel [SAY|PARTY|RAID|GUILD|<channel>]` — Set active trivia channel.
- `/trivia choices` — Toggle A/B/C/D multiple-choice options.
- `/trivia lock` | `/trivia unlock` | `/trivia disable` | `/trivia enable` | `/trivia button reset` — Manage moveable button.
- `/trivia skip` | `/trivia shuffle` | `/trivia clear` | `/trivia score` | `/trivia mem` | `/trivia help` — Game actions & memory status.

## Credits & License

- **Original Addon:** Roadblock (Nostalrius), Guri (Trollbane), Psy (Frostwolf), LizardBerry (Turtle WoW)
- **License:** Same as the original addon.
