# Mobile Game "Dopamine Hub" - LLM Development Prompts

This document contains the core architecture and specific logic prompts required to build the "Dopamine Hub" in Godot 4.

---

## 1. Core Shell: The "Feed Hub"
**Prompt:**
> "Write a Godot 4 GDScript for a 'Feed Hub' system.
> 1. **Setup:** The scene root is a `ScrollContainer` with a `VBoxContainer` child.
> 2. **Injection:** Create an array of 6 scene paths. Loop through them and instantiate each as a child of the `VBoxContainer`.
> 3. **Ad Insertion:** After every 4 game scenes, instantiate and insert an `AdCard.tscn` scene.
> 4. **Snapping:** Implement a snapping scroll effect. Use a `Tween` to lerp `scroll_vertical` to the nearest `viewport_height` whenever the user stops scrolling (detected by a `Timer` that resets on `scroll_changed`).
> 5. **Lazy Lifecycle:** Create `update_active_states()`. This checks which scene is centered in the `ScrollContainer`. Call `set_process(true)` / `set_physics_process(true)` on the centered scene, and `set_process(false)` / `set_physics_process(false)` on all others to save performance.
> 6. **Isolation:** Each game container must be a `SubViewportContainer` to isolate input and prevent UI overlap."

---

## 2. Game Logic Prompts

### Perfect Tap (Reflex)
> "Create a Godot 4 reflex game. A `Sprite2D` 'Orb' moves horizontally across the screen via a `Tween` (TRANS_SINE, REPEAT). A fixed 'TargetZone' exists in the bottom-center. On tap, if `abs(orb.x - target.x) < 50`, trigger 'Hit' (increase speed +5%, play sound). Otherwise, trigger 'Miss' (reset speed, shake screen, reset game)."

### Pirate Duel (PvP/Physics)
> "Create a 2D physics game. Two `RigidBody2D` ships (top/bottom). On drag-and-release, instantiate a `Cannonball` (Area2D) with a velocity vector equal to the drag distance/direction. If a cannonball hits the enemy ship, decrement HP. If cannonball A hits cannonball B, both `queue_free()`. AI ship: use a `Timer` to fire random-angle cannonballs at the player every 3s."

### Growth Chain (Tension)
> "Create a circle `Area2D` that scales up when the player holds the screen (+0.5 scale per frame). The screen has invisible boundaries (`StaticBody2D`). If the circle hits the boundary: `game_over()` (reset scale to 1.0). If player releases before hitting the boundary: bank points (current scale value) and reset circle to 1.0."

### Apex Climb (Infinite Climber)
> "Create a physics climber. Player is a `RigidBody2D`. On tap-and-drag, create a `SpringJoint2D` anchor to a platform. On release, apply `LinearVelocity` in the flick direction. Generate platforms procedurally 200px above the highest platform. If player falls below the camera view, reset game."

### Symmetry (Zen Order)
> "Create 8 nodes in a circle. Each has rotation property [0, 90, 180, 270]. On click, rotate a node 90 degrees. Add `check_win()` function: if all nodes == 0 rotation, trigger win (particle burst, randomize board after 0.5s delay)."

### Velocity Drift (Arcade Speed)
> "Create a top-down racer. Player (CharacterBody2D) has constant forward velocity. Hold to 'Drift' (steer angle 45, speed 5). Release to 'Straight' (steer 0, speed 10). The road is a `Path2D`. If player hits the road edge collision boundary while in 'Straight' mode, `game_over()`."

---

## 3. Monetization Integration

### Global Singleton: `AdManager.gd`
> "Create a Godot 4 Autoload script named `AdManager.gd`.
> 1. Track `games_played` (int). 
> 2. Function `on_game_finished()`: increments `games_played`. 
> 3. If `games_played % 5 == 0`, call `show_interstitial()`. 
> 4. `show_interstitial()` must set `get_tree().paused = true`, display an ad placeholder, and on ad-close, set `get_tree().paused = false`."

---

## 4. Implementation Rules for LLM
*   **Engine:** Godot 4.x / GDScript 2.0.
*   **Performance:** All games must define `set_process(false)` and `set_physics_process(false)` by default.
*   **UI:** Use a clean, flat-design palette (High contrast colors, simple shapes).
*   **Robustness:** No "Wait" commands; use `Timer` nodes or `Tweens` for all timing logic.