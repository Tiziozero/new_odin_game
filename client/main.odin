#+feature dynamic-literals
package main

import raylib "vendor:raylib"
import "core:fmt";
import "core:strings";
import "core:mem";
import "project:common/game"
import "project:common/networking"
apply_camera :: proc(camera: raylib.Rectangle, v: raylib.Vector2) -> raylib.Vector2 {
    return v - game.rect_pos(camera);
};
unapply_camera :: proc(camera: raylib.Rectangle, v: raylib.Vector2) -> raylib.Vector2 {
    return v + game.rect_pos(camera);
};

State :: struct {
    player_handle: int,
    entities: map[int]game.Entity,
    player_velocity: raylib.Vector2,
    camera: raylib.Rectangle,

    frame_arena: mem.Dynamic_Arena,
    logs: [dynamic]string,
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
draw_entity :: proc(camera: raylib.Rectangle, e: ^game.Entity) {
    p := apply_camera(camera, game.rect_pos(e.body));
    raylib.DrawRectangleV(p, game.rect_size(e.body), raylib.BLUE);
}
handle_input :: proc(e: ^InputEvent, state: ^State) {
    player_disp := raylib.Vector2{0,0};
    #partial switch e.kind {
    case .IE_KEY_DOWN:
    {
        #partial switch e.k {
        case .A: player_disp.x -= 1;
        case .D: player_disp.x += 1;
        case .W: player_disp.y -= 1;
        case .S: player_disp.y += 1;
        case:
        }
    }
    case:
    }
    state.player_velocity += player_disp;
}
get_dt :: proc() -> f32 {
    return raylib.GetFrameTime();
}
state_loop :: proc(s: ^State) {
    mem.dynamic_arena_reset(&s.frame_arena);
    clear(&s.logs);
}
init_game_con :: proc() {
}
main :: proc() {
    fmt.printfln("Hellppe")
    player := game.Entity{};
    player.body.x = 100;
    player.body.y = 100;
    player.body.width = 100;
    player.body.height = 100;
    raylib.InitWindow(4*SCREEN_SCALE, 3*SCREEN_SCALE, "Hellope!");
    events: [dynamic]InputEvent;
    s := State{};
    mem.dynamic_arena_init(&s.frame_arena);
    f := raylib.LoadFont("font.ttf");
    s.camera = raylib.Rectangle{
        4*SCREEN_SCALE, 3*SCREEN_SCALE,
        player.body.x, player.body.y};
    // main loop
    for !raylib.WindowShouldClose() {
        append(&s.logs, "Hello, World!!")
        rl_to_game(&events);
        append(&s.logs, "events!");
        append(&s.logs, fmt.aprintf("pos :%.0f %.0f", player.body.x, player.body.y, allocator = s.frame_arena.block_allocator));
        for &k in events {
            handle_input(&k, &s);
        }
        player.body.x += s.player_velocity.x * 100 * get_dt();
        player.body.y += s.player_velocity.y * 100 * get_dt();

        // update camera
        s.camera.x = player.body.x - 4*SCREEN_SCALE/2 + player.body.width/2;
        s.camera.y = player.body.y - 3*SCREEN_SCALE/2 + player.body.height/2;

        raylib.BeginDrawing();
        raylib.ClearBackground(raylib.PURPLE);
        draw_entity(s.camera, &player);
        // raylib.DrawRectangleRec(player.body, raylib.WHITE);
        i : i32= 0;
        for l in s.logs {
            cstr, err := strings.clone_to_cstring(l, s.frame_arena.block_allocator);
            raylib.DrawTextEx(f, cstr, raylib.Vector2{10, f32(10 + 24*i)}, 24, 2, raylib.WHITE);
            i += 1;
        }
        state_loop(&s);
        raylib.EndDrawing();
        clear(&events);
        s.player_velocity = raylib.Vector2{0,0};
    }
    raylib.UnloadFont(f);
    // init networking state
}
