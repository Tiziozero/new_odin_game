#+feature dynamic-literals
package main

CELLS := 80;

import "core:time"
import "core:mem"
import "core:os"
import "core:fmt"
import "core:strings"
import "networking"
import rl "vendor:raylib" 

vec2 :: rl.Vector2;
rect :: rl.Rectangle;
t2d :: rl.Texture2D;
SCREEN_SIZE :: vec2{1200,900}

rect_size :: proc(r: rect) -> vec2 {
    return vec2{r.width, r.height};
}
rect_pos :: proc(r: rect) -> vec2 {
    return vec2{r.x, r.y};
}


ItemKind :: enum {
    IkSpell, // spells?
};

Item :: struct {
    kind: ItemKind,
    has_ability: bool
};
MapInteractable :: struct {
    // zone for interacting
    body, zone: rl.Rectangle,
};
Vec2i :: struct { x, y: int };
Map :: struct {
    interactables: map[int]MapInteractable,
    chunks: map[Vec2i]MapChunk,
}
game :: struct {
    wmap: Map,
    prints: bool,
    config: GameConfig,
    current_handle: int,
    entities: map[int]Entity,
    mouse_pos: vec2,
    player_handle: int,
    camera: rect,
    dt: f32,
    textures: map[int]t2d,
    frame_arena: mem.Dynamic_Arena,
    logs_arena: mem.Dynamic_Arena,
    logs :[dynamic]Log,
    projectiles :[dynamic]Projectile,
    effects :[dynamic]Effect,
    collisions: [dynamic]struct{handle: int, dist: f32},

    dbg_sb: strings.Builder,
    // for player control
    player_velocity: rl.Vector2,
    ability_slots: [5]Item,
    items :[40]Item,
};
Log :: struct {
    time: time.Time,
    msg: string,
}
Wall :: struct {
    body: rl.Rectangle,
    color: rl.Color
}

game_add_projectile :: proc(game: ^game, p: ^Projectile) {
    p.active = 1;
    for pr, i in game.projectiles {
        if pr.active == 0 {
            p.index = i;
            game.projectiles[i] = p^;
            return;
        }
    }
    p.index = len(game.projectiles);
    append(&game.projectiles, (p^))
}
game_remove_projectile :: proc(game: ^game, index: int) {
    if index >= len(game.projectiles) {
        fmt.panicf("index > game.projectiles: %d %d", index, len(game.projectiles));
    }
    if game.projectiles[index].active == 0 {
        fmt.panicf("projectile %d is already inactive", index);
    }
    game.projectiles[index].active = 0;
}

EntityHandler :: proc(game: ^game, handle: int);

EntityStatus :: enum {
    ESDEAD = 0,
    ESALIVE,
    ESDYING,
    ESON=ESALIVE,
};
Entity :: struct {
    status: EntityStatus,
    handle: int,
    texture: int, // texture key for game.textures
    body: rect,
    direction: vec2,
    atk, def, health, max_health, speed: f32,
    payload: rawptr,
    update, draw: EntityHandler,
    abilities: [5]Ability // for entities and what not?
}
get_env :: proc(s: string) -> string {
    ret := os.get_env(s, context.allocator);
    fmt.printfln("-- got %s from get_env", ret);
    return ret;
}

apply_camera :: proc(game: ^game, v: vec2) -> vec2 {
    return v - rect_pos(game.camera);
};
unapply_camera :: proc(game: ^game, v: vec2) -> vec2 {
    return v + rect_pos(game.camera);
};

draw_entity :: proc(game: ^game, e: ^Entity) {
    draw_healt := false;
    // chech it's within camera
    if e.body.x > game.camera.x + game.camera.width ||
        e.body.x + e.body.width < game.camera.x {
        return;
    }
    if e.body.y > game.camera.y + game.camera.height ||
        e.body.y + e.body.height < game.camera.y {
        return;
    }
    origin := rect_size(e.body) * 0.5; // origin for raylib draw pro
    rotation : f32 = 0.0; // rodation
    // dest to draw, is center of body so add origin
    dest := apply_camera(game, rect_pos(e.body) + origin);
    img, ok := game.textures[e.texture];
    if !ok {
        fmt.panicf("failed to get image for index %d\n", e.texture);
    } else {
    }
    rl.DrawTexturePro(img,
        rect{0, 0, f32(img.width), f32(img.height)},
        rect{dest.x, dest.y, e.body.width, e.body.height},
        origin, rotation, rl.WHITE);
}
entity_new :: proc(txt_handle: int, x, y, w, h, max_health, atk, def: f32) -> Entity {
    e : Entity;
    e.texture = txt_handle;
    e.body.x = x;
    e.body.y = y;
    e.body.width = w;
    e.body.height = h;
    e.atk = atk;
    e.def = def;
    e.max_health = max_health;
    e.health = max_health;
    e.speed = 200;
    return e;
};
game_add_entity :: proc(game: ^game, e: ^Entity) -> int {
    e.handle = game.current_handle;
    game.entities[game.current_handle] = e^; // will copy
    game.current_handle += 1; // increment
    return e.handle;
}
game_remove_entity :: proc(game: ^game, handle: int) -> int {
    delete_key(&game.entities, handle); // delete_key
    return 1;
}
game_new ::proc() -> game {
    g : game;
    g.wmap = get_map();
    g.entities = map[int]Entity{};
    g.textures = map[int]t2d{};
    g.current_handle = 0;
    mem.dynamic_arena_init(&g.logs_arena);
    mem.dynamic_arena_init(&g.frame_arena);
    strings.builder_init(&g.dbg_sb, g.frame_arena.block_allocator);
    return g;
}
game_loop :: proc(game: ^game) {
    game.player_velocity= vec2{0,0};
    strings.builder_reset(&game.dbg_sb);
    mem.dynamic_arena_reset(&game.frame_arena);
}
game_free :: proc(game: ^game) {
    // textures
    for _, v in game.textures {
        rl.UnloadTexture(v);
    }
    delete(game.textures);
    delete(game.entities);

    // dynamic arrays
    delete(game.logs);
    delete(game.projectiles);
    delete(game.effects);
    delete(game.collisions);

    // arenas (these free all their blocks)
    mem.dynamic_arena_destroy(&game.frame_arena);
    mem.dynamic_arena_destroy(&game.logs_arena);

    // builders backed by arenas are already freed above,
    // but reset the builder metadata
    strings.builder_destroy(&game.dbg_sb);

    // config
    delete(game.config.ui_input);
    fmt.printfln("freed game.");
}
draw_entities_sorted :: proc(game: ^game, allocator := context.allocator) {
    handles := make([]int, len(game.entities), allocator)
    i := 0
    for handle in game.entities {
        handles[i] = handle
        i += 1
    }
    // insertion sort — fast for nearly-sorted data each frame
    for i := 1; i < len(handles); i += 1 {
        key := handles[i]
        j := i - 1
        for j >= 0 && game.entities[handles[j]].body.y > game.entities[key].body.y {
            handles[j + 1] = handles[j]
            j -= 1
        }
        handles[j + 1] = key
    }
    for handle in handles {
        e := &game.entities[handle]
        if e.status != .ESDEAD {
            draw_entity(game, e)
        }
    }
    delete(handles);
}
get_dt :: proc() -> f32 {
    return f32(rl.GetFrameTime())
}
game_load_texture :: proc(game: ^game, path: string) -> int {
    cstr_path := strings.clone_to_cstring(path);
    t := rl.LoadTexture(cstr_path);
       if t.id == 0 {
           fmt.panicf("what. rl texture id is 0");
       }
    delete(cstr_path);
    game.textures[int(t.id)] = t;
    return int(t.id);
}
Tile :: struct {
    c: int,
};
cells :: 16;

random_from_coords :: proc(i, j, s: int, a, b: int) -> int {
    // Mix inputs into a single value (hash)
    x := i * 374761393 + j * 668265263 + s * 1442695040888963407
    x = (x ~ (x >> 13)) * 1274126177
    x = x ~ (x >> 16)

    // Ensure positive
    if x < 0 {
        x = -x
    }

    // Map to range [a, b]
    range := b - a + 1
    return a + (x % range)
}
get_draw_tile_f :: proc(game: ^game, i,j: int, f: f32) {
    // apply to draw pos, so * f
    d := apply_camera(game, vec2{f32(i*cells)*f, f32(j*cells)*f});
    c := random_from_coords(i, j, 69, 0, 2);
    src := rect{x=304 + f32(cells*c),y=16,
              width=cells, height=cells};
               // again dest is draw pos, so * f
    dest := rect{d.x, d.y, cells*f32(f), cells*f32(f)};
    color : rl.Color;
    if c == 1 {
        color = rl.WHITE
    } else if c == 2 {
        color = rl.RED
    } else if c == 0 {
        color = rl.BLUE
    }
    rl.DrawRectangleRec(dest,color);
}
entity_ability_act :: proc(game: ^game, e: ^Entity, index: int) {
    if e.abilities[index].active == 0 {
        fmt.printfln("ability %d is inactive.", index);
        return;
    }
    ability := &e.abilities[index];
    ability.act(game, ability, e);
}
// define later
Damage :: f32;
game_damage_entity :: proc(game: ^ game, handle: int, damage: Damage) {
    e, ok := &game.entities[handle];
    if !ok {
        fmt.panicf("No entity %d", handle);
    }
    // formulae for now
    dmg := (1-e.def/1000) * damage;
    fmt.println("Damaging entity", handle, "health", e.health, "for", dmg);
    e.health -= dmg;
    if e.health <= 0 {
        fmt.println("Entity dies.");
        game_remove_entity(game, handle);
    }
}
InputHandler :: struct {
    action: proc(game: ^game),
}
GameConfig :: struct {
    // ui keys
    ui_input: map[rl.KeyboardKey]InputHandler
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
    k : rl.KeyboardKey,
    mb : rl.MouseButton,
    click: rl.Vector2,
}
rl_to_game :: proc(events: ^[dynamic]InputEvent) {
    clear(events);
    // Keyboard
    for keyc := 0; keyc < 348; keyc += 1 {
        k := rl.KeyboardKey(keyc);

        if rl.IsKeyPressed(k) {
            append(events, InputEvent{
                kind = .IE_KEY_PRESSED,
                k    = k,
            });
        }

        if rl.IsKeyDown(k) {
            append(events, InputEvent{
                kind = .IE_KEY_DOWN,
                k    = k,
            });
        }
    }

    // Mouse buttons to check
    buttons := [?]rl.MouseButton{.LEFT, .RIGHT, .MIDDLE};

    for mb in buttons {
        // Pressed (click)
        if rl.IsMouseButtonPressed(mb) {
            append(events, InputEvent{
                kind  = .IE_MB_PRESSED,
                mb    = mb,
                click = rl.GetMousePosition(),
            });
        }

        // Held
        if rl.IsMouseButtonDown(mb) {
            append(events, InputEvent{
                kind = .IE_MB_DOWN,
                mb   = mb,
            });
        }
    }
}
game_get_entity_line_collisions :: proc(game:^ game, p1, p2: rl.Vector2) -> [dynamic]struct{handle: int, dist: f32} {
    clear(&game.collisions);
    for k, e in game.entities {
        r := e.body;
        if line_rect_intersect(p1, p2, r) {
            d := line_rect_shortest_dist(p1, p2, r);
                v :struct{handle: int, dist: f32}; 
                v.dist = d;
                v.handle = k;
                append(&game.collisions, v);
        }
    }
    return game.collisions;
}
game_dbg :: proc(game: ^game, fmt_str: string, args: ..any) {
    fmt.sbprintfln(&game.dbg_sb, fmt_str, ..args);
    buf: [time.MIN_HMS_LEN]u8
}
game_log :: proc(game: ^game, fmt_str: string, args: ..any) {
    l: Log
    sb: strings.Builder
    strings.builder_init(&sb, game.logs_arena.block_allocator)

    buf: [time.MIN_HMS_LEN]u8
    ts := time.time_to_string_hms(time.now(), buf[:])
    fmt.sbprintf(&sb, "%s ", ts)
    fmt.sbprintf(&sb, fmt_str, ..args)

    l.msg = strings.to_string(sb)
    append(&game.logs, l)
}

get_map :: proc() -> Map {
    m: Map;
    return m;
}
/*
The key insight is push out on the shallowest overlap axis — if you're barely clipping a wall on the left but deeply overlapping on the top, you're hitting the side, not the top. Resolving the smaller overlap is almost always correct.
   */
entity_wall_collision :: proc(body, wall: ^rl.Rectangle) -> bool {
    // horizontal overlap
        if !rl.CheckCollisionRecs(body^, wall^) do return false;

            // compute overlap on each axis
            overlap_x := min(body.x + body.width,  wall.x + wall.width)  - max(body.x, wall.x)
            overlap_y := min(body.y + body.height, wall.y + wall.height) - max(body.y, wall.y)

            // push out on shallowest axis
            if overlap_x < overlap_y {
                if body.x < wall.x {
                    body.x -= overlap_x
                } else {
                    body.x += overlap_x
                }
            } else {
                if body.y < wall.y {
                    body.y -= overlap_y
                } else {
                    body.y += overlap_y
                }
            }
    return true;
}
draw_bg :: proc(game: ^game) {
    f :f32 = f32(CELLS)/f32(cells); // scale factor
    p := &game.entities[game.player_handle];
    // draw walls
    cx := int(p.body.x/f32(CHUNK_SIZE*CELLS));
    cy := int(p.body.y/f32(CHUNK_SIZE*CELLS));
    // get chunks around it
    for i in cx-2..=cx+2 {
        for j in cy-2..=cy+2 {
            chunk, ok := game.wmap.chunks[{i, j}];
            tiles := chunk.tiles;
            for x in 0..<CHUNK_SIZE {
                for y in 0..<CHUNK_SIZE {
                    xp := f32(i*CHUNK_SIZE*CELLS + x* CELLS) // get tile x/y pos
                    yp := f32(j*CHUNK_SIZE*CELLS + y* CELLS)
                    cam_pos := apply_camera(game, rl.Vector2{xp, yp});
                    if cam_pos.x + f32(CELLS) < 0 ||
                        cam_pos.x  > game.camera.width {
                            continue;
                    }
                    if cam_pos.y + f32(CELLS) < 0 ||
                        cam_pos.y > game.camera.height {
                            continue;
                    }
                    color : rl.Color;
                    c := tiles[y*CHUNK_SIZE+x].c;
                    if c == 1 {
                        color = rl.WHITE
                    } else if c == 2 {
                        color = rl.RED
                    } else if c == 0 {
                        color = rl.BLUE
                    }
                    rl.DrawRectangleV(cam_pos, rl.Vector2{f32(CELLS), f32(CELLS)},color);
                }
            }

            walls := chunk.walls;
            for w in walls {
                cam_pos := apply_camera(game, rect_pos(w.body));
                if cam_pos.x + w.body.width < 0 ||
                    cam_pos.x  > game.camera.width {
                        continue;
                    }
                if cam_pos.y + w.body.height < 0 ||
                    cam_pos.y > game.camera.height {
                        continue;
                }
                fmt.println("Drawing wall", cam_pos, w.color);
                rl.DrawRectangleV(cam_pos, rect_size(w.body), w.color);
            }
        }
    }
}
// isometric fn: I(x,y)=((x-y)/\sqrt{2},(x+y)/(\sqrt{2}*k))
// for future bs
main :: proc() {
    if networking.nmain() != 0 {
        return
    }
    // a = 1.1 - 1.7 seems to be ok-sih? defo rework. lower number are awkward
    for i in 0..=100 {
        fmt.printfln(" === %3d === %10f", i, scale_damage(f32(i),100,5, 104_420, 1.7));
    }
    fmt.printfln("Hello %s", get_env("a"));
    fmt.println("Hellp, World loop!");
    // init game/ctx
    rl.InitWindow(1200,900, "Entricity");
    rl.SetExitKey(.KEY_NULL);
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);
    // game config
    gc : GameConfig;
    gc.ui_input = map[rl.KeyboardKey]InputHandler{
        // escape closes window
        .ESCAPE=InputHandler{action=proc(game: ^game){
            fmt.println("Close window called via exit.");
            rl.CloseWindow();
        }},
        .P=InputHandler{action=proc(game: ^game){
            game.prints = false;
        }},
    };

    game := game_new();
    game.config = gc;

    player_tx_handle := game_load_texture(&game, "imgs/apple.png");
    player := entity_new(player_tx_handle, 100, 100, 80, 80, 65, 100, 5);
    player.update = proc(game: ^game, handle: int) {
    };
    player.draw = proc(game: ^game, handle: int) {
        draw_entity(game, &game.entities[handle]);
    };
    player_handle := game_add_entity(&game, &player);

    enemy1_tx_handle := game_load_texture(&game, "imgs/banana.png");
    enemy1 := entity_new(enemy1_tx_handle, 200, 200, 100, 100, 50, 100, 5);
    enemy1.update = proc(game: ^game, handle: int) {
    };
    enemy1.draw = proc(game: ^game, handle: int) {
        draw_entity(game, &game.entities[handle]);
    };
    enemy1_handle := game_add_entity(&game, &enemy1);

    // player abilities
    {
        p := &game.entities[player_handle];
           a: Ability = init_base(&game, p, 0);
              a.active = 1;
              p.abilities[0] = a;
    }

    handle_game_input :: proc(e: InputEvent, game: ^game) {
        // game first, then player
        if e.kind == .IE_KEY_PRESSED {
            if handler, ok := &game.config.ui_input[e.k]; ok {
                handler.action(game);
            } else {
                fmt.println("No action found for key", e.k);
            }
        }
        handle_player_input(e, game, &game.entities[game.player_handle], game.dt);
    }
    handle_player_input :: proc(e: InputEvent, game: ^game, p: ^Entity, dt: f32) {
        if e.kind == .IE_KEY_DOWN {
            if e.k == .A {
                game.player_velocity.x -= 1;
            }
            if e.k == .D {
                game.player_velocity.x += 1;
            }
            if e.k == .W {
                game.player_velocity.y -= 1;
            }
            if e.k == .S {
                game.player_velocity.y += 1;
            }
        } else if e.kind == .IE_KEY_PRESSED {
            if e.k == .SPACE {
                entity_ability_act(game, p, 0);
            }
        } else if e.kind == .IE_MB_PRESSED {
            if e.mb == .LEFT {
                entity_ability_act(game, p, 0);
            }
        }

    }
    events: [dynamic]InputEvent;
    for !rl.WindowShouldClose() {
        {
            player := game.entities[player_handle];
            // cam pos is player center - half screen size
            campos := rect_pos(player.body) + // get camera pas
                        rect_size(player.body)/2 - SCREEN_SIZE/2;
            camsize := SCREEN_SIZE;
            game.camera.x = campos.x
            game.camera.y = campos.y
            game.camera.width = camsize.x
            game.camera.height = camsize.y
        }
        // get dt
        game.dt = get_dt();
        // handle input
        rl_to_game(&events);
        for e in events {
            handle_game_input(e, &game);
        }
        { // update player TODO: make more efficient, someday maybe
            p := &game.entities[game.player_handle];
            player_center_screen_pos := apply_camera(&game,
                                      rect_pos(p.body) + 0.5* rect_size(p.body));
            mp := rl.GetMousePosition();
            d := rl.Vector2Normalize(mp - player_center_screen_pos);
            p.direction = d;
            if game.player_velocity.x == 0 && game.player_velocity.y == 0 {
            } else {
                pv := rl.Vector2Normalize(game.player_velocity);
                p.body.x += pv.x * p.speed * game.dt;
                p.body.y += pv.y * p.speed * game.dt;
                // set direction
                cx := int(p.body.x/f32((CHUNK_SIZE*CELLS)));
                cy := int(p.body.y/f32((CHUNK_SIZE*CELLS)));
                // fmt.println("cx cy:", cx, cy, p.body.x, p.body.y);
                // get chunks around it
                for i in cx-2..=cx+2 {
                    for j in cy-2..=cy+2 {
                        _, ok := game.wmap.chunks[{i, j}];
                        if !ok {
                            c := gen_chunck(&game.wmap, i, j);
                            game.wmap.chunks[{i, j}] = c;
                        }
                    }
                }
                chunk:= game.wmap.chunks[{cx, cy}];
                // check collisions  in all 9 chunks around player
                for i in cx-1..=cx+1 {
                    for j in cy-1..=cy+1 {
                        walls := game.wmap.chunks[{i, j}].walls;
                        for &w in walls {
                               entity_wall_collision(&p.body, &w.body);
                        }
                    }
                }
            }
        }
        // update entities
        for handle in game.entities {
            e := &game.entities[handle]
            // upadate ailities first.
            for i in 0..<len(e.abilities) {
                a := &e.abilities[i];
                if a.active == 0 {
                    continue;
                }
                a.update(&game, a, e);
            }
        }
        // update projectiles - p needs to be a reference
        inactive_p := 0;
        for i in 0..<len(game.projectiles) {
            p := &game.projectiles[i];
            if p.active != 1 {
                inactive_p += 1;
            } else {
                p.update(&game, p);
            }
        }

        rl.BeginDrawing();
        rl.ClearBackground(rl.BLACK);
        draw_bg(&game);
        // draw entities
        // draw_entities_sorted(&game);
        for k, e in game.entities {
            e.draw(&game, k);
        }
        // draw projectiles
        for i in 0..<len(game.projectiles) {
            p := &game.projectiles[i];
            if p.active == 1 {
                p.draw(&game, p);
            }
        }
        rl.DrawFPS(10,10);
        game_dbg(&game, "dt:\t%f\nentities:\t%d\nprojectiles:\t%d",
            game.dt,
            len(game.entities),
            len(game.projectiles));
        s := strings.to_cstring(&game.dbg_sb);
        rl.DrawRectangle(0,0,200,900, rl.Color{75,75,75,200});
        rl.DrawText(s, 10, 40, 20, rl.BLACK);
        rl.EndDrawing();
        game_loop(&game);
    }
    game_free(&game);
    delete(events);
}
