# desktop-waifu Feature Roadmap

Features to build into desktop-waifu, taken from the companion-app analysis in
`temp/lilith_interactive_menu_analysis.md` and adapted to this project. Each item says
what's needed and how it fits the current code. Store/Steam-specific mechanics are left
out or swapped for local equivalents.

**Size:** S = an evening, M = a few days, L = a week or more.
**Status:** ✅ done · 🟡 partly done · ⬜ not started

## Already in place

| Feature | Status | Where |
|---|---|---|
| Drag-and-drop the character | ✅ | `DraggedState` |
| Sit on the taskbar | ✅ | `SittingState` |
| Sit on other windows' title bars, follow them, fall off when they close | ✅ | `PerchedState`, `WindowTracker` |
| Speech bubble with random lines | ✅ | `SpeechBubble`, `DesktopPet.say_random_line()` |
| Right-click context menu (Talk / Sit / Quit) | ✅ | `DesktopPet._build_context_menu()` |
| Spine skeleton with idle, wave, walk, drag, fall, sit | ✅ | `assets/characters/waifu/` |
| Settings and save data with live `changed(key)` updates (F-0.1) | ✅ | `Settings`, `SaveData` autoloads (`scripts/data/`) |
| Move her across monitors | 🟡 | The overlay window only covers the current screen. See F-W3. |

---

## Phase 0: Foundations

Most later features depend on these, so they come first.

### F-0.1 Settings and save data (S) ✅
- One `Settings` autoload that loads and saves a `ConfigFile` at `user://settings.cfg`.
  It holds window flags, volumes, schedule, wardrobe choice, whitelist, and so on.
- Separate `user://save.json` for progress: affection, unlocked topics, memories,
  notes, reminders.
- Emit a `changed(key)` signal so open menus and the pet update live.

### F-0.2 System tray icon (M)
- Use Godot's `StatusIndicator` node (Windows supported) with a `PopupMenu`.
- This is where settings live when she's hidden or click-through is on, and where the
  menus in F-S1 go.
- Left-click the tray icon to show or hide her.

### F-0.3 Tell click, double-click and drag apart (S)
- Right now any left press on her starts a drag at once. Change `PetState.handle_input`
  so a press only becomes a pickup after the cursor moves past a few pixels or the button
  is held for about 150 ms.
- A press and release with no movement counts as a click. Two clicks within the OS
  double-click time count as a double-click.
- F-1.1, F-1.2 and F-1.3 all depend on this.

### F-0.4 Body-part hit regions (M)
- Add Spine **bounding-box attachments** for head, face, chest, hands and skirt in
  `waifu.spine-json`. They follow the bones, so they still hit correctly mid-animation.
- New `DesktopPet.get_body_part(point) -> StringName` that tests the point against those
  boxes, falling back to `&"body"`.
- Fallback if the bounding boxes are hard to query from GDScript: compute rectangles
  from bone world positions (`SpineSprite.get_skeleton().find_bone()`).

### F-0.5 Dialogue data (S)
- Move lines out of `@export` arrays into data files, e.g. `res://data/dialogue/*.json`,
  keyed by trigger (`idle`, `grab`, `pat`, `poke_face`, `perch`, `morning`, ...).
- Support conditions (time of day, affection level, mood, outfit) and an optional
  expression or animation for each line.

### F-0.6 Expressions (M)
- Add face attachments to the skeleton: eyes (open, closed, happy ^^, surprised,
  sleepy) and mouth (smile, open, pout).
- Add short one-shot animations: `pat`, `shy`, `happy`, `surprised`, `pout`.
- Needs new art drawn into the atlas. The generator script, `draw_atlas.ps1`, isn't in
  the repo yet; move it to `tools/` first.

### F-0.7 Audio (S)
- Add `Voice` and `SFX` audio buses with volume controlled from Settings.
- Play a short sound when a line appears (blip or chime) until real voice lines exist.

---

## Phase 1: Interaction and touch

### F-1.1 Headpats (M)
- Press on the head and rub side to side to give continuous pats. Track horizontal
  direction changes while the button is held on the `head` region.
- Patting plays the `pat` loop with happy eyes, shows affection lines, and raises
  affection (F-2.5).
- A press on the head that moves mostly vertically, or holds still, still picks her up
  as before.

### F-1.2 Reactions per body part (S, after F-0.4 and F-0.6)
- A single click on face, chest, hands or skirt gives its own line and expression.
- Skirt and chest clicks get a flustered or pouty reaction. Poking her face too often
  makes her annoyed for a while.

### F-1.3 Double-click opens the Talk menu (S)
- Double-click opens the Talk menu (Phase 2) next to her, in place of the current
  right-click menu's "Say something".
- The menu is a separate window, like `ContextMenu`, so it isn't clipped by the
  click-through region.

### F-1.4 Drag across monitors (M, see F-W3)

---

## Phase 2: Talk menu

A themed menu (a `PopupMenu` or a small `Window` with buttons) opened by double-click
or from the tray.

### F-2.1 Snack Time (M)
- She plays the `sit` pose next to a cushion or sofa prop (a Spine slot, so the wardrobe
  can change it).
- Offers up to N daily conversation topics. Each topic is a short scripted dialogue
  with expressions.
- The topic pool rotates daily (seeded by date), and seen topics unlock in Memories
  (F-2.4).

### F-2.2 Mood check-in: "How was your day?" (S)
- 3–5 answers (great, okay, tired, stressed, bad), each with a fitting reply.
- Store one entry per day in `save.json` for a simple mood history.

### F-2.3 Talk about feelings (S)
- Branching mini-dialogues built from the same dialogue data as F-0.5, with 2–3 choices
  per node.

### F-2.4 Memories gallery (M)
- A list of unlocked Snack Time topics, milestone lines (first headpat, first perch,
  affection levels) and story events, each replayable.

### F-2.5 Affection (S)
- One number in save data, raised by pats, talking and daily check-ins, and lowered
  slightly by neglect or too much poking.
- Thresholds unlock lines, topics and outfits.

---

## Phase 3: Productivity tools ("Jot something down" / "Keep time for me")

### F-3.1 Scratchpad (S)
- A small always-on-top `Window` with a `TextEdit`, autosaved to `user://notes.txt`.

### F-3.2 Reminders from plain text (M)
- Typing "call mom at 18:30" or "meeting tomorrow 9am" in the scratchpad or a quick-add
  box creates a reminder.
- Parse a small set of patterns: `HH:MM`, `at 6pm`, `in 20 min`, `tomorrow`, weekday
  names and `dd/mm`.
- When due, she walks to the centre, waves (`idle_action`) and shows the reminder in her
  bubble until it's clicked.

### F-3.3 Memos, calendar, recurring alerts (M)
- A list view of reminders with edit and delete, repeat rules (daily, weekdays, weekly)
  and countdowns ("3 days until ...").

### F-3.4 Timer and alarm (S)
- Countdown timer and alarm from the Talk menu or tray. She announces when it fires.
  Use a `Timer` plus wall-clock checks so sleep and wake don't break it.

### F-3.5 Folder watcher (M)
- Watch a chosen folder (e.g. Downloads) and comment when files appear: "Your download
  finished!"
- Reuse the WindowTracker pattern: a long-lived PowerShell helper with
  `System.IO.FileSystemWatcher` writing events to stdout, read on a worker thread.
  Godot has no file-system watcher of its own.

### F-3.6 Music (M)
- First step: media keys (play/pause, next, previous) by sending `VK_MEDIA_*` through a
  helper using `keybd_event`. This works with Spotify, browsers and most players.
- Later: show the current track and react to it, via the Windows
  `GlobalSystemMediaTransportControlsSessionManager`. That's WinRT, so it needs a small
  compiled helper rather than PowerShell 5.1.
- Optional: a dance or bob animation while music plays.

---

## Phase 4: Behaviour that reacts to context

### F-4.1 Detect full-screen games and apps (M)
- Extend the `WindowTracker` helper to report the foreground window's process name and
  whether it covers its whole monitor.
- When a full-screen app is in front, she goes to a new `Watching` state: changes into
  pajamas or casual clothes and lies on the taskbar edge to "watch". She goes quiet:
  no wandering and no bubbles unless clicked.
- A whitelist and blacklist of executables in Settings (F-S2), so a full-screen video
  player can be handled differently from a game.

### F-4.2 Sleep schedule (M)
- Bedtime set in Settings (F-S1). About 2 hours before, she changes into pajamas and
  starts yawning lines.
- At bedtime she asks "Can I go to sleep?" with Yes or Stay up. If you choose Stay up,
  she asks again later.
- Asleep: a new `Sleeping` state with a lying-down animation, Zzz bubble and blanket
  slot. Clicking wakes her briefly.

### F-4.3 Tuck her in (S)
- If you keep her up past a hard limit, she falls asleep without a blanket. A "Tuck her
  in" action (click or menu) shows the blanket and a sleepy thank-you.

### F-4.4 Greetings by time of day (S)
- Good morning, lunch and late-night lines based on the clock, plus "welcome back" after
  the PC was idle or asleep (check for a jump in the system clock).

### F-4.5 Smarter perching (S)
- Use the existing tracker for: hopping onto the active window on her own now and then;
  refusing title bars that are covered on drop *and* while sitting (currently she stays
  on top); and briefly hiding when a window is dragged over her.

---

## Phase 5: Wardrobe

### F-5.1 Outfits as Spine skins (M)
- Each cosmetic is a **Spine skin** that swaps attachments in its slots. Combine skins
  at runtime: base + outfit + hat + glasses (`SpineSkin.add_skin` through
  `SpineSprite`).
- Categories: **Outfit** (casual), **Pajamas**, **Hat**, **Glasses**, **Bedding**
  (sleep state only), **Cushion/Sofa** (Snack Time only).
- Needs hat and glasses slots on the head bone, and blanket and sofa slots on root.

### F-5.2 Wardrobe UI (M)
- A tray menu entry that opens a window with category tabs and a live preview (a second
  `SpineSprite` in the window).
- The choice is saved in Settings. Pajamas and bedding switch automatically with the
  schedule (F-4.2).

### F-5.3 Unlocks without Steam (S)
- Replace Steam item drops with local unlocks: affection milestones, daily login streaks,
  Snack Time completions.
- Optional: a rarity label for display only. Skip the duplicate-exchange system.

---

## Settings and system tray menu

### F-S1 Tray menu layout (M, after F-0.2)
```
Character ▸  Wardrobe…
             Schedule…   (bedtime, rest reminders)
Settings  ▸  Game whitelist…
             Always on top          [✓]
             Click-through mode     [ ]
             Monitor ▸  Primary / Monitor 2 / Follow mouse
             Volume ▸  Voice / SFX
Hide for 30 min / Hide until restart
Quit
```

### F-S2 Game whitelist (S)
- A list of executable names, editable in a small window, used by F-4.1.

### F-W1 Always-on-top toggle (S)
- Wire `get_window().always_on_top` to Settings. `main.gd` currently forces it on at
  startup.

### F-W2 Click-through mode (S)
- When on, pass an empty polygon to `DisplayServer.window_set_mouse_passthrough` so the
  whole window ignores clicks. She can only be reached from the tray.

### F-W3 Multiple monitors (L)
- Option A: one overlay window per monitor, with the pet handed between them when
  dragged past an edge.
- Option B: one overlay covering the bounding box of all usable areas. This is simpler,
  but needs per-monitor floors (taskbar heights) and gaps between monitors handled.
- Also needs the `WindowTracker` coordinate maths checked for monitors with different
  DPI.

### F-W4 Hide and exit (S)
- Hide with a timer ("back in 30 minutes"), with a goodbye or welcome-back line.

### F-W5 Rest reminders (S)
- An optional "stand up and stretch" or "drink water" nudge every N minutes.

---

## Suggested order

1. **F-0.3** gestures, **F-0.1** settings, **F-0.2** tray. Everything else hangs off
   these.
2. **F-0.4** hit regions + **F-0.6** expressions → **F-1.1** headpats, **F-1.2**
   reactions, **F-2.5** affection. This makes the biggest difference to how she feels.
3. **F-1.3** Talk menu + **F-0.5** dialogue data → **F-2.2** mood check-in, **F-2.1**
   Snack Time.
4. **F-3.1** scratchpad, **F-3.4** timer, **F-3.2** reminders. The most useful tools in
   daily use.
5. **F-4.2** sleep schedule + **F-5.1** skins (pajamas first) → **F-4.1** game detection.
6. Everything else: memories, wardrobe UI, music, folder watcher, multiple monitors.

## Art needed

New features need new skeleton parts and animations. Group art work so the atlas
changes in batches:

- **Expressions:** eye and mouth variants; `pat`, `shy`, `happy`, `surprised`, `pout`
  animations.
- **Sleep:** lying-down pose, `sleep` loop, blanket, pajamas skin.
- **Snack Time:** cushion or sofa prop, sitting-and-chatting variant.
- **Wardrobe:** at least one hat and one pair of glasses to prove the skin system works.
- **Watching:** a lying-on-the-taskbar pose.
