#+feature dynamic-literals
package main

import raylib "vendor:raylib"
import "core:net";
import "core:fmt";
import "project:common/game"
import "project:common/networking"

State :: struct {
    player_handle: player
    entities: map[int]game.Entity,
    projectiles: map[int]game.Entity,
};
InputHandler :: struct {
    action: proc(game: ^State),
}
InputEventKind :: enum {
    IE_CLICK,
    IE_KEY_PRESSED,
    IE_KEY_DOWN,
    IE_MB_PRESSED, // mouse button
    IE_MB_DOWN,
};
InputEvent :: struct {
    kind : InputEventKind,
    k : raylib.KeyboardKey,
    mb : raylib.MouseButton,
    click: raylib.Vector2,
}
rl_to_game :: proc(events: ^[dynamic]InputEvent) {
    clear(events);
    // Keyboard
    for keyc := 0; keyc < 348; keyc += 1 {
        k := raylib.KeyboardKey(keyc);

        if raylib.IsKeyPressed(k) {
            append(events, InputEvent{
                kind = .IE_KEY_PRESSED,
                k    = k,
            });
        }

        if raylib.IsKeyDown(k) {
            append(events, InputEvent{
                kind = .IE_KEY_DOWN,
                k    = k,
            });
        }
    }

    // Mouse buttons to check
    buttons := [?]raylib.MouseButton{.LEFT, .RIGHT, .MIDDLE};

    for mb in buttons {
        // Pressed (click)
        if raylib.IsMouseButtonPressed(mb) {
            append(events, InputEvent{
                kind  = .IE_MB_PRESSED,
                mb    = mb,
                click = raylib.GetMousePosition(),
            });
        }

        // Held
        if raylib.IsMouseButtonDown(mb) {
            append(events, InputEvent{
                kind = .IE_MB_DOWN,
                mb   = mb,
            });
        }
    }
}
SCREEN_SCALE :: 300;
main :: proc() {
    fmt.printfln("Hellppe")
    raylib.InitWindow(4*SCREEN_SCALE, 3*SCREEN_SCALE, "Hellop!");
    for !raylib.WindowShouldClose() {
        raylib.BeginDrawing();
        raylib.ClearBackground(raylib.PURPLE);
        raylib.EndDrawing();
    }
    // init networking state
}
