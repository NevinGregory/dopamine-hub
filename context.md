# Dopamine Hub — Project Context

## What is it?

A **mobile game compilation app** built in **Godot 4.6** — a single download that hosts 6 micro-games in a vertically scrolling feed (TikTok/Reels-style). Players scroll, play, and get served interstitial ads between sessions.

## Project Structure

```
dopamine-hub/                    # Godot project root
├── project.godot                # Godot 4.6, Mobile renderer, Jolt Physics
├── scenes/
│   ├── feed_hub/FeedHub.tscn    # Core swipe feed control
│   ├── games/
│   │   ├── perfect_tap/         # Reflex game
│   │   ├── pirate_duel/         # PvP physics game
│   │   ├── growth_chain/        # Tension hold-and-release
│   │   ├── apex_climb/          # Infinite climber
│   │   ├── symmetry/            # Zen rotation puzzle
│   │   └── velocity_drift/      # Arcade top-down racer
│   └── ads/AdCard.tscn          # Ad placeholder card
├── scripts/
│   ├── feed_hub/FeedHub.gd      # Swipe feed logic + infinite loop
│   ├── ads/AdCard.gd             # Ad card placeholder
│   └── managers/AdManager.gd    # Autoload: tracks plays, interstitial ads
├── assets/                      # Art, audio, fonts (empty folders)
└── icon.svg
```

## The 6 Micro-Games

| Game | Genre | Core Loop |
|---|---|---|
| **Perfect Tap** | Reflex | Tap a moving orb inside a target zone; speed increases on hit, resets on miss |
| **Pirate Duel** | PvP/Physics | Drag-and-release cannonballs at an enemy ship with AI opponent |
| **Growth Chain** | Tension | Hold to grow a circle, release to bank points — don't hit the walls |
| **Apex Climb** | Infinite Climber | Flick a physics body upward on procedurally generated platforms |
| **Symmetry** | Zen Puzzle | Rotate 8 nodes to all-0 orientation to win |
| **Velocity Drift** | Arcade Racer | Hold-to-drift top-down racer on a Path2D road |

## Architecture Pillars

- **Swipe-based feed** — not a ScrollContainer. A `Control` root with a transparent overlay detects vertical swipes (>60px threshold) and Tweens between cards.
- **SubViewportContainer isolation** — each game runs in its own viewport to prevent input conflicts and UI overlap.
- **Lazy lifecycle** — only the visible card processes; all others are frozen (`set_process(false)`).
- **Tap passthrough** — quick taps (<60px movement) are forwarded to the current card's SubViewport via `push_input()`. Swipes (>60px) are consumed to navigate cards.
- **Infinite loop** — 3 rotating card slots (prev/current/next) are recycled infinitely. After all 6 games are shown, they're reshuffled for the next cycle.
- **Randomized ad insertion** — ads are inserted into the shuffle queue at random intervals (every 3-5 games).
- **AdManager singleton** — tracks games played, shows interstitial every 5 plays, pauses/resumes the tree.
- **No `await`/`wait`** — all timing via `Timer` or `Tween`.
- **Clean flat-design palette** — high contrast colors, simple shapes.

## Caveats & Future Concerns

- **Gesture conflict (⚠️ untested)** — The swipe-vs-tap threshold (60px) may conflict with games that use drag gestures (e.g., Pirate Duel's drag-to-fire cannonball, Apex Climb's flick). If a game's drag exceeds the threshold, it will trigger a card navigation instead. Possible solutions: edge-only swipe zones, per-game threshold overrides, or navigation buttons as a fallback.

## Key Design Decisions

- Each game scene has a `Node2D` → `Control` → `ColorRect` structure with distinct colors for visual identification during feed testing.
- Game logic scripts will be written per-game (none yet).
- Assets folders exist but are empty — no art, audio, or fonts imported yet.
- Mobile-friendly: mobile renderer, Jolt Physics 3D (for 2D physics via Godot's 2D engine).

## Development Prompts

The full spec document is at `game_hub_prompts.md` in this directory. It contains detailed LLM prompts for each game's logic, the feed hub shell, and monetization integration.
