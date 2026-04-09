package main

import "core:mem"
import "core:os"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib" 

GameContext :: struct {
    frame_arena: mem.Dynamic_Arena,
    game: game,
}

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
game :: struct {
    current_handle: int,
    entities: map[int]Entity,
    mouse_pos: vec2,
    player_handle: int,
    camera: rect,
    dt: f32,
    textures: map[int]t2d,
    frame_arena: mem.Dynamic_Arena,
    projectiles :[dynamic]Projectile,
    effects :[dynamic]Effect,
    collisions: [dynamic]struct{handle: int, dist: f32}
};

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
    abilities: [5]Ability
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
    g.entities = map[int]Entity{};
    g.textures = map[int]t2d{};
    g.current_handle = 0;
    return g;
}
game_free :: proc(game: ^game) {
    for l, v in game.textures {
        rl.UnloadTexture(v);
    }
    delete(game.entities);
    delete(game.textures);
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
    ability := e.abilities[index];
    ability.act(game, &ability, e);
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

// isometric fn: I(x,y)=((x-y)/\sqrt{2},(x+y)/(\sqrt{2}*k))
// for future bs
main :: proc() {
    // a = 1.1 - 1.7 seems to be ok-sih? defo rework. lower number are awkward
    for i in 0..=100 {
        fmt.printfln(" === %3d === %10f", i, scale_damage(f32(i),100,5, 104_420, 1.7));
    }
    fmt.printfln("Hello %s", get_env("a"));
    fmt.println("Hellp, World loop!");
    // init game/ctx
    rl.InitWindow(1200,900, "Entricity");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    game := game_new();

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

    handle_player_input :: proc(game: ^game, p: ^Entity, dt: f32) {
        pv: vec2;
        if rl.IsKeyDown(.A) {
            pv.x -= 1;
        }
        if rl.IsKeyDown(.D) {
            pv.x += 1;
        }
        if rl.IsKeyDown(.W) {
            pv.y -= 1;
        }
        if rl.IsKeyDown(.S) {
            pv.y += 1;
        }
        if rl.IsKeyPressed(.SPACE) {
            entity_ability_act(game, p, 0);
        }
        if rl.IsMouseButtonPressed(.LEFT) {
            entity_ability_act(game, p, 0);
        }

        pv = rl.Vector2Normalize(pv);
        p.body.x += pv.x * p.speed * dt;
        p.body.y += pv.y * p.speed * dt;
        // set direction
        player_center_screen_pos := apply_camera(game,
                                      rect_pos(p.body) + 0.5* rect_size(p.body));
        mp := rl.GetMousePosition();
        d := rl.Vector2Normalize(mp - player_center_screen_pos);
        p.direction = d;
    }
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
        // handle player input
        handle_player_input(&game, &game.entities[player_handle], game.dt);
        // update entities
        for handle, e in game.entities {
            e.update(&game, handle);
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
        { // draw bg
            f :f32 = 5; // scale factor
            player := game.entities[player_handle];
            px: = int(player.body.x / (cells*f)); // multiply cells by factor
            py: = int(player.body.y / (cells*f));
            range := 10
            for i in px-range..=px+range {
                for j in py-range..=py+range {
                    get_draw_tile_f(&game, i, j, f);
                }
            }
        }
        // draw entities
        for handle, e in game.entities {
            e.draw(&game, handle);
        }
        // draw projectiles
        for i in 0..<len(game.projectiles) {
            p := &game.projectiles[i];
            if p.active == 1 {
                p.draw(&game, p);
            }
        }
        rl.DrawFPS(10,10);
        sb : strings.Builder;
        strings.builder_init(&sb);
        fmt.sbprintfln(&sb,
            "dt:\t%f", game.dt);
        fmt.sbprintfln(&sb,
            "entities:\t%d", len(game.entities));
        fmt.sbprintfln(&sb,
            "projectiles:\t%d", len(game.projectiles));
        cstr := strings.unsafe_to_cstring(&sb);
        rl.DrawText(cstr, 10, 40, 20, rl.BLACK);
        delete(cstr);
        
        rl.EndDrawing();
        draw_entities_sorted(&game);
    }

    game_free(&game);
}
