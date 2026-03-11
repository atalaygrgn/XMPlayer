# XMPlayer Architecture and System Flow

## 1) Purpose and Scope

XMPlayer is a Love2D-based media suite for muOS devices. It provides:
- XMB-style navigation for media categories
- Music playback inside Love2D
- Video playback through external MPV process
- Photo viewing with pan/zoom
- Persistent indexing, settings, history, and watched state

This document describes the architecture after the recent model/view separation refactor.

## 2) High-Level Architecture

The codebase follows a layered modular style:

- Composition and lifecycle layer:
  - [.xmplayer/main.lua](.xmplayer/main.lua)
- Navigation controller layer:
  - [.xmplayer/modules/xmb.lua](.xmplayer/modules/xmb.lua)
- View layer:
  - [.xmplayer/modules/xmb_draw.lua](.xmplayer/modules/xmb_draw.lua)
  - [.xmplayer/modules/music_view.lua](.xmplayer/modules/music_view.lua)
  - [.xmplayer/modules/image_view.lua](.xmplayer/modules/image_view.lua)
  - [.xmplayer/modules/settings_view.lua](.xmplayer/modules/settings_view.lua)
  - [.xmplayer/modules/background.lua](.xmplayer/modules/background.lua)
  - [.xmplayer/modules/ui.lua](.xmplayer/modules/ui.lua)
- Model/service layer:
  - [.xmplayer/modules/music_player.lua](.xmplayer/modules/music_player.lua)
  - [.xmplayer/modules/image_viewer.lua](.xmplayer/modules/image_viewer.lua)
  - [.xmplayer/modules/settings.lua](.xmplayer/modules/settings.lua)
  - [.xmplayer/modules/browser.lua](.xmplayer/modules/browser.lua)
  - [.xmplayer/modules/indexing.lua](.xmplayer/modules/indexing.lua)
  - [.xmplayer/modules/player.lua](.xmplayer/modules/player.lua)
  - [.xmplayer/modules/video_manager.lua](.xmplayer/modules/video_manager.lua)
  - [.xmplayer/modules/history.lua](.xmplayer/modules/history.lua)
  - [.xmplayer/modules/system.lua](.xmplayer/modules/system.lua)
  - [.xmplayer/modules/metadata.lua](.xmplayer/modules/metadata.lua)
  - [.xmplayer/modules/utils.lua](.xmplayer/modules/utils.lua)
- Static data/config layer:
  - [.xmplayer/modules/categories.lua](.xmplayer/modules/categories.lua)
  - [.xmplayer/modules/theme.lua](.xmplayer/modules/theme.lua)
  - [.xmplayer/modules/assets.lua](.xmplayer/modules/assets.lua)
  - [.xmplayer/conf.lua](.xmplayer/conf.lua)

Core design rule:
- Controllers mutate state.
- Views render and handle presentation-level input only.
- Services perform IO and external integration.

## 3) Runtime Modes and Screen Ownership

At runtime, drawing and input route through one active mode at a time:

1. Music mode
- Condition: music_player.active
- Draw: music_view.draw
- Input: music_view.keypressed

2. Photo viewer mode
- Condition: image_viewer.active
- Draw: image_view.draw
- Input: image_view.keypressed

3. Indexing mode
- Condition: indexing.is_scanning
- Draw: ui.draw_indexing_popup
- Input: no special route, update is mostly coroutine progress

4. XMB mode (default)
- Condition: none of the above
- Draw: xmb_draw.draw + HUD in main
- Input: xmb.keypressed

## 4) Main Loop Flow

Implemented in [.xmplayer/main.lua](.xmplayer/main.lua).

### love.load

1. Load assets and fonts
2. Init subsystems (background, music model, music view, image viewer model)
3. Load settings and apply theme/path-related side effects
4. Load media index data
5. If index is missing/empty, start coroutine scan
6. Else initialize browser through xmb.refresh_browser
7. Prime battery/charging/volume/brightness cache via system module

### love.update

1. If player.needs_refresh, recreate Love2D window mode after MPV returns
2. Update current active mode:
- Music: music_player.update
- Photo viewer: image_viewer.update
- Indexing: resume scan coroutine and return early
- Else: xmb.update
3. Poll battery and charging on slower interval
4. Poll volume and brightness on fast interval for toast notifications
5. Update background animation and toast lifetimes

### love.draw

1. Hard clear screen
2. Draw animated background
3. Draw active mode surface
4. If in XMB mode, draw top HUD (clock, battery)
5. Draw toasts last

### love.keypressed

1. If music mode active, route to music_view
2. Else if photo mode active, route to image_view
3. Else route to xmb controller

## 5) Navigation and Data Composition (XMB)

Controller:
- [.xmplayer/modules/xmb.lua](.xmplayer/modules/xmb.lua)

Renderer:
- [.xmplayer/modules/xmb_draw.lua](.xmplayer/modules/xmb_draw.lua)

### Responsibilities split

xmb.lua:
- Keeps current category, item focus, submenu stack
- Builds browser.files list based on category and view_type
- Handles actions: open file, open folder, open subview, play all/shuffle, settings operations
- Manages animation state values consumed by xmb_draw

xmb_draw.lua:
- Draws category row, item list, icons/thumbnails, watched overlays
- Draws settings popup through settings_view
- Reads state only

### view_type state machine

Primary values:
- category_root
- browser
- music_albums
- music_artists
- album_tracks
- artist_tracks
- video_resume

Transitions are driven by selected item.type and back navigation.

### Browser integration

xmb uses browser as a generic list source and stateful directory scanner:
- browser.set_state(base_dir, current_dir, filter)
- browser.scan()
- browser.set_files(list)

This avoids direct field mutation and keeps responsibilities explicit.

## 6) Media Services

## 6.1 Music

Model:
- [.xmplayer/modules/music_player.lua](.xmplayer/modules/music_player.lua)

View:
- [.xmplayer/modules/music_view.lua](.xmplayer/modules/music_view.lua)

Flow:
1. xmb selects a track or shuffle source
2. music_player.play builds playlist and loads selected track
3. metadata is read for tags/cover art
4. Love2D Source is created and played
5. update handles fade, elapsed time, auto-next, marquee progression
6. music_view renders UI and handles playback controls

## 6.2 Video

External player bridge:
- [.xmplayer/modules/player.lua](.xmplayer/modules/player.lua)

Resume and watched tracking:
- [.xmplayer/modules/video_manager.lua](.xmplayer/modules/video_manager.lua)
- [.xmplayer/modules/history.lua](.xmplayer/modules/history.lua)

Flow:
1. xmb action calls player.play_video
2. history records first entry
3. control mapping switches to MPV via gptokeyb2
4. mpv command runs blocking
5. on return, control mapping switches back to Love
6. player.needs_refresh triggers display reset in main.update

Watched/resume behavior:
- Resume entries read from mpv watch_later directory
- Mark watched toggles persistent watched map
- Mark watched clears matching resume file

## 6.3 Photos

Model:
- [.xmplayer/modules/image_viewer.lua](.xmplayer/modules/image_viewer.lua)

View:
- [.xmplayer/modules/image_view.lua](.xmplayer/modules/image_view.lua)

Flow:
1. xmb opens selected image with current file list
2. model builds image-only playlist and index
3. image loads into Love2D image object
4. update applies fade and pan controls
5. view draws image, overlay, and zoom/navigation key handlers

## 7) Indexing Pipeline

Module:
- [.xmplayer/modules/indexing.lua](.xmplayer/modules/indexing.lua)

Data output:
- music.files
- music.albums
- music.artists
- photos with thumbnail info
- videos list

Execution model:
- Full scan runs in coroutine from main
- Scan yields regularly to keep UI responsive
- Progress text exposed via indexing.scan_progress

Persistence:
- Index is stored in index.cfg and loaded on startup
- Photo thumbnails generated/cached under thumbnails directory

## 8) Settings and Theme System

Model:
- [.xmplayer/modules/settings.lua](.xmplayer/modules/settings.lua)

Popup view:
- [.xmplayer/modules/settings_view.lua](.xmplayer/modules/settings_view.lua)

Theme:
- [.xmplayer/modules/theme.lua](.xmplayer/modules/theme.lua)

Flow:
1. settings.load reads saved values
2. settings.apply propagates side effects:
- theme mode/accent
- category media root paths
- keytone enable
- volume/brightness toast enable
- particle toggle
- wallpaper options via background module
3. xmb integrates settings groups/options as browser items
4. settings_view handles animated selection popup for choice options

## 9) UI and Background Rendering

UI toolkit:
- [.xmplayer/modules/ui.lua](.xmplayer/modules/ui.lua)

Background compositor:
- [.xmplayer/modules/background.lua](.xmplayer/modules/background.lua)

Capabilities:
- Marquee component with timed phases
- Glow text/icon rendering and gloss shader
- Toast notifications (generic + volume + brightness)
- Indexing popup
- Animated gradient, optional wallpaper modes, particles
- Music-reactive waveform

## 10) Device/System Integration

Hardware query boundary:
- [.xmplayer/modules/system.lua](.xmplayer/modules/system.lua)

Queries:
- Battery percentage
- Charging state
- Volume level
- Brightness level

This module isolates muOS-specific file paths from generic utility logic.

## 11) Persistent Data and Files

Storage root:
- love.filesystem.getSource()

Primary runtime files:
- settings.cfg
- index.cfg
- history.cfg
- watched.cfg
- thumbnails/
- config/mpv/watch_later/

Runtime asset/config dependencies:
- [.xmplayer/assets](.xmplayer/assets)
- [.xmplayer/config](.xmplayer/config)
- [.xmplayer/bin](.xmplayer/bin)

## 12) Dependency Direction

Preferred dependency direction:
- main -> controllers/views/services
- xmb controller -> services/models
- views -> read model/controller state, no ownership of business data
- services -> IO/external processes/persistence

Avoid:
- model importing view modules
- view mutating unrelated service internals
- direct mutation of browser/settings shared state from many locations without APIs

## 13) End-to-End System Flows

## 13.1 Startup flow

1. main.load
2. assets.load
3. settings.load -> settings.apply
4. indexing.load
5. branch:
- index exists: xmb.refresh_browser
- index missing: start coroutine indexing.scan
6. render frame loop begins

## 13.2 Play video flow

1. User selects video item in xmb
2. player.play_video invoked
3. history.add
4. Switch input mapper to mpv profile
5. Execute mpv process
6. Return from mpv
7. Switch mapper back to Love profile
8. Set player.needs_refresh
9. main.update resets window mode and resumes app

## 13.3 Change settings flow

1. User enters settings category in xmb
2. xmb builds group/option list from settings model
3. On choice option, settings_view popup opens
4. User chooses value
5. settings.apply and settings.save
6. xmb refreshes settings item list and keeps focus where appropriate

## 14) Extension Points for New Features

Recommended places to extend:
- New category:
  - Add entry in [.xmplayer/modules/categories.lua](.xmplayer/modules/categories.lua)
  - Add icon in assets load
  - Add category branch logic in xmb.refresh_items and action handling
- New settings option:
  - Add option/group in settings model
  - Apply side effect in settings.apply if needed
  - settings_view handles generic choice popup automatically
- New media metadata/display field:
  - Add parse in metadata/indexing
  - Render in corresponding view module
- New toast type:
  - Add producer in service/controller
  - Add renderer path in ui.draw_toasts

## 15) Current Architectural Strengths

- Clear model-view split for XMB, music, image, settings popup
- External process integration isolated in player module
- Hardware integration isolated in system module
- Navigation and rendering now decoupled for easier maintenance
- Persistent concerns separated (settings/index/history/watched)

## 16) Known Constraints

- Lua language server may flag Love global symbol as undefined outside Love runtime
- Directory scanning uses shell commands for muOS compatibility
- MPV launch is blocking by design
- Some modules still rely on shared mutable tables; API boundaries are improved but not fully immutable

## 17) Quick Module Index

- Composition entry: [.xmplayer/main.lua](.xmplayer/main.lua)
- Navigation controller: [.xmplayer/modules/xmb.lua](.xmplayer/modules/xmb.lua)
- Navigation renderer: [.xmplayer/modules/xmb_draw.lua](.xmplayer/modules/xmb_draw.lua)
- Music model/view: [.xmplayer/modules/music_player.lua](.xmplayer/modules/music_player.lua), [.xmplayer/modules/music_view.lua](.xmplayer/modules/music_view.lua)
- Image model/view: [.xmplayer/modules/image_viewer.lua](.xmplayer/modules/image_viewer.lua), [.xmplayer/modules/image_view.lua](.xmplayer/modules/image_view.lua)
- Settings model/view: [.xmplayer/modules/settings.lua](.xmplayer/modules/settings.lua), [.xmplayer/modules/settings_view.lua](.xmplayer/modules/settings_view.lua)
- Browser/indexing: [.xmplayer/modules/browser.lua](.xmplayer/modules/browser.lua), [.xmplayer/modules/indexing.lua](.xmplayer/modules/indexing.lua)
- Video/history: [.xmplayer/modules/player.lua](.xmplayer/modules/player.lua), [.xmplayer/modules/video_manager.lua](.xmplayer/modules/video_manager.lua), [.xmplayer/modules/history.lua](.xmplayer/modules/history.lua)
- UI/background/theme/assets: [.xmplayer/modules/ui.lua](.xmplayer/modules/ui.lua), [.xmplayer/modules/background.lua](.xmplayer/modules/background.lua), [.xmplayer/modules/theme.lua](.xmplayer/modules/theme.lua), [.xmplayer/modules/assets.lua](.xmplayer/modules/assets.lua)
- Generic/system utilities: [.xmplayer/modules/utils.lua](.xmplayer/modules/utils.lua), [.xmplayer/modules/system.lua](.xmplayer/modules/system.lua)

## 18) Developer Onboarding

This section is a practical guide for adding features without breaking architecture boundaries.

### 18.1 First-day orientation

Read these files in this order:
1. [.xmplayer/main.lua](.xmplayer/main.lua)
2. [.xmplayer/modules/xmb.lua](.xmplayer/modules/xmb.lua)
3. [.xmplayer/modules/xmb_draw.lua](.xmplayer/modules/xmb_draw.lua)
4. [.xmplayer/modules/settings.lua](.xmplayer/modules/settings.lua)
5. [.xmplayer/modules/indexing.lua](.xmplayer/modules/indexing.lua)
6. [ARCHITECTURE.md](ARCHITECTURE.md)

This gives you the lifecycle, controller flow, render flow, persistence model, and extension points.

### 18.2 Where to look by feature type

- New screen/view rendering:
  - Start with [.xmplayer/modules/xmb_draw.lua](.xmplayer/modules/xmb_draw.lua) for XMB content
  - Or create a dedicated view module like music/image views and route from [.xmplayer/main.lua](.xmplayer/main.lua)

- New navigation behavior:
  - [.xmplayer/modules/xmb.lua](.xmplayer/modules/xmb.lua)

- New persistent setting:
  - [.xmplayer/modules/settings.lua](.xmplayer/modules/settings.lua)
  - If choice popup is needed, [.xmplayer/modules/settings_view.lua](.xmplayer/modules/settings_view.lua)

- New file scanning/indexed data:
  - [.xmplayer/modules/indexing.lua](.xmplayer/modules/indexing.lua)
  - Metadata extraction in [.xmplayer/modules/metadata.lua](.xmplayer/modules/metadata.lua)

- New style/theme/font/icon:
  - [.xmplayer/modules/theme.lua](.xmplayer/modules/theme.lua)
  - [.xmplayer/modules/assets.lua](.xmplayer/modules/assets.lua)

- New external integration (process/system):
  - Video/process flow: [.xmplayer/modules/player.lua](.xmplayer/modules/player.lua)
  - Device polling paths: [.xmplayer/modules/system.lua](.xmplayer/modules/system.lua)

### 18.3 Feature development playbook

Use this sequence for almost every feature:

1. Define feature category:
- UI-only
- controller behavior
- model/service behavior
- persistence/schema change
- external integration

2. Choose the owning module first (single source of truth)
- Avoid implementing the same behavior in both controller and view

3. Add or update data contracts
- item types in xmb list entries
- settings option shape
- indexing data shape

4. Implement logic in model/service or controller

5. Render in view layer only

6. Wire entry points in main only if mode routing changes

7. Verify key flows:
- startup
- navigation/back flow
- settings save/load
- media playback transitions

8. Update [ARCHITECTURE.md](ARCHITECTURE.md) if architectural behavior changed

### 18.4 Concrete recipes

#### Add a new top-level category

1. Add category object to [.xmplayer/modules/categories.lua](.xmplayer/modules/categories.lua)
2. Add icon asset and load mapping in [.xmplayer/modules/assets.lua](.xmplayer/modules/assets.lua)
3. Add category branch in xmb refresh logic in [.xmplayer/modules/xmb.lua](.xmplayer/modules/xmb.lua)
4. Add actions for new item types in xmb.keypressed in [.xmplayer/modules/xmb.lua](.xmplayer/modules/xmb.lua)
5. If special rendering is needed, update [.xmplayer/modules/xmb_draw.lua](.xmplayer/modules/xmb_draw.lua)
6. Validate left/right category transitions and back behavior

#### Add a new settings option

1. Add option entry in [.xmplayer/modules/settings.lua](.xmplayer/modules/settings.lua)
2. Ensure it belongs to an existing or new group in same file
3. Implement side effects in settings.apply
4. If value is persisted, no extra work needed because save/load is generic
5. If choice-based, settings_view popup works automatically
6. If action-based, handle action in xmb key handling branch

#### Add a new toast/notification

1. Add trigger function in [.xmplayer/modules/ui.lua](.xmplayer/modules/ui.lua) or call existing show_toast
2. Add rendering branch in ui.draw_toasts if special visualization is needed
3. Emit toast from appropriate owner:
- controller (navigation action)
- service callback/result
- settings action

#### Add a new indexed metadata field

1. Extract in [.xmplayer/modules/metadata.lua](.xmplayer/modules/metadata.lua)
2. Store in [.xmplayer/modules/indexing.lua](.xmplayer/modules/indexing.lua)
3. Render in target view:
- [.xmplayer/modules/music_view.lua](.xmplayer/modules/music_view.lua)
- [.xmplayer/modules/xmb_draw.lua](.xmplayer/modules/xmb_draw.lua)
4. Keep backward compatibility for existing index.cfg content when possible

### 18.5 Design rules to keep code clean

- Keep view modules stateless where possible:
  - read state, draw UI, map input to model/controller calls

- Keep xmb as orchestration layer, not rendering layer

- Keep browser state updates through APIs:
  - browser.set_state
  - browser.set_files

- Keep device-specific paths in system module only

- Keep heavy IO off hot render path:
  - do scans in coroutine
  - cache thumbnails and index data

- Keep naming explicit:
  - *_view for rendering modules
  - nouns for models/services

### 18.6 Common pitfalls and how to avoid them

- Pitfall: duplicating behavior in controller and view
  - Fix: place business logic in xmb/model; view only forwards

- Pitfall: mutating shared tables from many places
  - Fix: add small API methods in owner module

- Pitfall: breaking back navigation semantics
  - Fix: test xmb.nav_stack transitions for every new item type

- Pitfall: blocking UI with long operations
  - Fix: use coroutine + yield points as in indexing.scan

- Pitfall: adding new settings but forgetting apply side effects
  - Fix: always update settings.apply when adding option ids

- Pitfall: stale docs after architecture changes
  - Fix: update [ARCHITECTURE.md](ARCHITECTURE.md) in same PR

### 18.7 Minimal validation checklist before merge

Functional:
1. App starts with existing settings/index files
2. Category left/right navigation works
3. Back behavior works in all affected submenus
4. Music/photo/video flows still open and close correctly
5. Settings persist across restart

Architecture:
1. No rendering logic added into model/service modules
2. No business flow added into view-only modules
3. New state has a clear owner module
4. New file/folder names follow existing conventions

Operational:
1. No accidental platform junk files committed
2. No hardcoded paths outside intended modules
3. New assets are loaded through assets module

### 18.8 Suggested PR structure for new features

1. Commit 1: data/model changes
2. Commit 2: controller and routing changes
3. Commit 3: view rendering changes
4. Commit 4: docs update in [ARCHITECTURE.md](ARCHITECTURE.md)

This keeps review easy and reduces regression risk.
