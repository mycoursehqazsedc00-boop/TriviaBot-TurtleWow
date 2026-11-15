# TriviaBot-TurtleWoW (Patched & Expanded for WoW 1.12 / Turtle WoW)

> An interactive in-game chat trivia host for Vanilla WoW 1.12 and Turtle WoW featuring multiple-choice (A/B/C/D) questions, fuzzy ("likely") answer matching, a moveable on-screen control button, and 4,010 questions across Turtle WoW custom content, pre-2007 Warcraft I–III & WoW lore publications, World Geography, and General Knowledge Trivia.

## Client Mods Used

| Mod | Purpose in this addon | Required? |
|---|---|---|
| **UnitXP SP3** | Optional taskbar icon flash notification (`UnitXP("notify", "taskbarIcon")`) when a player answers a question while `/trivia notify` is enabled | Optional |

*(The addon runs in Vanilla-Safe Lua 5.0 mode and works completely without any client DLL mods.)*

## Features

- **Moveable On-Screen Control Button (`TriviaBotToggleButton`):**
  - **Left-Click:** Start / Stop the trivia game immediately.
  - **Right-Click:** Skip the current question (when running) or cycle through question sets (when stopped).
  - **Drag:** Move anywhere on screen (position is saved across sessions in `TRIVIA_CONFIG`).
  - **Lock & Hide Controls:** Lock position with `/trivia lock` or hide/disable the button completely with `/trivia disable` (`/trivia enable` to restore).
- **Multiple Choice (A, B, C, D) & Flexible Answering:**
  - Every question displays 4 shuffled options (`A`, `B`, `C`, `D`).
  - Players can answer by typing the choice letter (`A`, `B`, `C`, `D`, `a)`, `option a`, etc.) OR by typing the answer text.
  - Built-in anti-spam protection prevents players from rapid-guessing all 4 letters at once (3-second per-player letter cooldown on a wrong letter guess).
- **Fuzzy / "Likely" Answer Matching:**
  - Accepts answers even if they are not typed verbatim: ignores capitalization, punctuation, and leading articles (`the`, `a`, `an`), matches number words to digits (`thirty five` <-> `35`), extracts core names/titles (`Lashlayer` for `Broodlord Lashlayer`, `Sorrowguard` for `Sorrowguard Keep`), and tolerates 1–3 character typos via zero-allocation Levenshtein edit distance on non-numeric answers.
- **6 Selectable Question Sets (4,010 Total Questions):**
  - `warcraft` (1,060 questions): Combined Turtle WoW + Vanilla 1.12 WoW + Warcraft I, II, III & Official Pre-2007 Lore Publications.
  - `turtle` (100 questions): Dedicated Turtle WoW custom content (High Elves, Goblins, Gilneas, Tel'Abim, Balor, Northwind, Grim Reaches, Alah'Thalas, Lower Karazhan Halls, Emerald Sanctum, Tower of Karazhan, Hateforge Quarry, Crescent Grove, Stormwind Vault, Black Morass, Survival, Gardening, Jewelcrafting, Hardcore & Challenge Glyphs, World Bosses, Class Changes).
  - `wow` (960 questions): Strictly pre-TBC (late 2006 or earlier) Vanilla 1.12 WoW + Warcraft I (*Orcs & Humans*), Warcraft II (*Tides of Darkness* & *Beyond the Dark Portal*), Warcraft III (*Reign of Chaos* & *The Frozen Throne*), and official pre-2007 Warcraft novels/manga (*Day of the Dragon*, *Lord of the Clans*, *Of Blood and Honor*, *The Last Guardian*, *War of the Ancients*, *Cycle of Hatred*, *The Sunwell Trilogy*).
  - `geography` (200 questions): World Capitals, Continents, Oceans, Rivers, Mountains, Landmarks & US Geography.
  - `normal` (2,750 questions): General Knowledge, Common Sense, Science, Astronomy, Math, Human Body, History, Literature, Art, Music, Sports, and World Trivia.
  - `all` (4,010 questions): All question sets combined.
- **Score Tracking & Speed Records:**
  - Automatically announces top 3 scorers and the fastest answer record every 5 questions.
  - Players in the trivia channel can type `score` (or `!score`) to receive their current score via whisper.

## What Was Added / Improved

- **Added:** Moveable on-screen toggle button (`TriviaBotToggleButton`) with status colors, rich tooltip, saved screen position, `/trivia lock` (`/trivia unlock`), `/trivia disable` (`/trivia enable`), and `/trivia button reset`.
- **Added:** Shuffled `A) ... | B) ... | C) ... | D) ...` multiple-choice options for all 4,010 questions across all 4 question files, with `/trivia choices` toggle and category-matched distractors.
- **Added:** Smart fuzzy ("likely") answer matcher supporting punctuation/article stripping, number-word conversion, core keyword extraction, and Levenshtein typo tolerance.
- **Added:** Expanded `TurtleQuestions.lua` (100 questions), `WoWQuestions.lua` (960 strictly pre-2007 Vanilla/Warcraft I–III/Novel questions), `GeographyQuestions.lua` (200 questions including basic world geography), and `NormalQuestions.lua` (2,750 questions including basic general-knowledge & common-sense trivia).
- **Fixed:** Audited and removed all TBC / WotLK / post-2006 questions, phrasing, and multiple-choice distractors from `WoWQuestions.lua` and `TurtleQuestions.lua`.
- **Fixed:** Fixed critical syntax errors in `WoWQuestions.lua` (line 99 mismatched quotes `'Regalia of Transcendence"` and line 348 trailing colon `:`) that previously prevented `WoWQuestions.lua` from loading at all.
- **Fixed:** Fixed missing question indices (`WoWQuestions.lua` indices 72 and 141; `GeographyQuestions.lua` index 75) that caused `nil` table holes and broke `table.getn` in Lua 5.0.
- **Fixed:** Fixed copy-paste bug in `Trivia_CheckAnswer` where `TRIVIA_ANSWERS4..8` were all comparing against `TRIVIA_ANSWERS3`.
- **Fixed:** Fixed `Trivia_DoSchedule` table mutation bug during iteration that skipped or dropped scheduled events.
- **Fixed:** Implemented missing `Trivia_WhisperScore` function (previously threw a nil global Lua error whenever someone typed `score` in channel).
- **Fixed:** Fixed channel event filtering so `SAY`, `PARTY`, `RAID` (including `CHAT_MSG_RAID_LEADER`), and `GUILD` only process answers from the active `TRIVIA_CHANNEL`.
- **Fixed:** Removed duplicate loading of `TriviaBot-TurtleWow.lua` between `.toc` and `.xml`.

## Usage

- `/trivia start` | `/trivia stop` | `/trivia toggle` — Start, stop, or toggle the trivia bot.
- `/trivia lock` | `/trivia unlock` — Lock or unlock the moveable on-screen button.
- `/trivia disable` | `/trivia enable` — Disable (hide) or enable (show) the on-screen button.
- `/trivia button reset` — Reset the moveable button to top-center of the screen.
- `/trivia qlist [warcraft|turtle|wow|geography|normal|all]` — Select the active question set.
- `/trivia channel [SAY|PARTY|RAID|GUILD|<custom channel>]` — Set the trivia output/input channel.
- `/trivia choices` — Toggle displaying A/B/C/D multiple-choice options in chat.
- `/trivia skip` — Skip the current question.
- `/trivia shuffle` — Reshuffle the active question set.
- `/trivia clear` — Clear current scores and speed records.
- `/trivia score` — Print current top scorers to the trivia channel.
- `/trivia notify` — Toggle optional UnitXP SP3 taskbar notification on correct answers.
- `/trivia help` — Display in-game command help.

## Credits & License

- **Original Addon:** Roadblock (Nostalrius), Guri (Trollbane), Psy (Frostwolf), LizardBerry (Turtle WoW)
- **Patch & Improvements:** Custom Turtle WoW & Warcraft Lore expansion, A/B/C/D choice engine, fuzzy matcher, and moveable UI button
- **License:** Same as the original addon.
