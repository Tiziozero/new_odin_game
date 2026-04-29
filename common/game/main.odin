#+feature dynamic-literals
package game
CELLS := 80;

import "core:time"
import "core:net"
import "core:mem"
import "core:os"
import "core:fmt"
import "core:strings"
import "vendor:raylib" 
import "project:common/networking"
import "project:common/buffer_io"

vec2    :: raylib.Vector2;
rect    :: raylib.Rectangle;
t2d     :: raylib.Texture2D;
color   :: raylib.Color;
SCREEN_SIZE :: vec2{1200,900}

EntityDelta :: struct {
    body: raylib.Rectangle,
    status: EntityStatus,
}

pack_entity :: proc(buf: ^buffer_io.Buffer, e: ^EntityDelta) {
    buffer_io.buffer_write_u32(buf, transmute(u32)e.status);
    buffer_io.buffer_write_f32(buf, e.body.x);
    buffer_io.buffer_write_f32(buf, e.body.y);
}
unpack_entity :: proc(buf: ^buffer_io.Buffer, e: ^EntityDelta) {
    new_status, ok := buffer_io.buffer_read_u32(buf);
    if !ok {
        fmt.panicf("Failed to read u32\n");
    }
    e.status = transmute(EntityStatus)new_status;
    e.body.x, ok = buffer_io.buffer_read_f32(buf);
    if !ok {
        fmt.panicf("Failed to read u32\n");
    }
    e.body.y, ok= buffer_io.buffer_read_f32(buf);
    if !ok {
        fmt.panicf("Failed to read u32\n");
    }
}

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
    body, zone: rect,
};
Vec2i :: struct { x, y: int };
Map :: struct {
    interactables: map[int]MapInteractable,
    chunks: map[Vec2i]MapChunk,
}
@private
Game :: struct {
    wmap: Map,
    current_handle: int, // current handle for new entities
    entities: map[int]Entity,
    dt: f32,
    frame_arena: mem.Dynamic_Arena,
    projectiles :[dynamic]Projectile,
    effects :[dynamic]Effect,
    collisions: [dynamic]struct{handle: int, dist: f32},
    items: [dynamic]Item,
};
Wall :: struct {
    body:   rect,
    color:  color,
}

game_add_projectile :: proc(game: ^Game, p: ^Projectile) {
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
game_remove_projectile :: proc(game: ^Game, index: int) {
    if index >= len(game.projectiles) {
        fmt.panicf("index > game.projectiles: %d %d",
            index, len(game.projectiles));
    }
    if game.projectiles[index].active == 0 {
        fmt.panicf("projectile %d is already inactive", index);
    }
    game.projectiles[index].active = 0;
}

EntityHandler :: proc(game: ^Game, handle: int);

EntityStatus :: enum u32 {
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
    update, draw: EntityHandler,
    abilities: [5]Ability // for entities and what not?
}
get_env :: proc(s: string) -> string {
    ret := os.get_env(s, context.allocator);
    fmt.printfln("-- got %s from get_env", ret);
    return ret;
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
game_add_entity :: proc(game: ^Game, e: ^Entity) -> int {
    e.handle = game.current_handle;
    game.entities[game.current_handle] = e^; // will copy
    game.current_handle += 1; // increment
    return e.handle;
}
game_remove_entity :: proc(game: ^Game, handle: int) -> int {
    delete_key(&game.entities, handle); // delete_key
    return 1;
}
game_new ::proc() -> Game {
    g : Game;
    g.wmap = get_map();
    g.entities = map[int]Entity{};
    mem.dynamic_arena_init(&g.frame_arena);
    return g;
}
game_loop :: proc(game: ^Game) {
    mem.dynamic_arena_reset(&game.frame_arena);
}
game_free :: proc(game: ^Game) {
    delete(game.entities);
    // dynamic arrays
    delete(game.projectiles);
    delete(game.effects);
    delete(game.collisions);

    // arenas (these free all their blocks)
    mem.dynamic_arena_destroy(&game.frame_arena);
    fmt.printfln("freed game.");
}
get_dt :: proc() -> f32 {
    fmt.panicf("TODO: implement get dt");
}
Tile :: struct {
    c: int,
};

entity_ability_act :: proc(game: ^Game, e: ^Entity, index: int) {
    if e.abilities[index].active == 0 {
        fmt.printfln("ability %d is inactive.", index);
        return;
    }
    ability := &e.abilities[index];
    ability.act(game, ability, e);
}
// define later
Damage :: f32;
game_damage_entity :: proc(game: ^ Game, handle: int, damage: Damage) {
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
game_get_entity_line_collisions :: proc(game:^ Game,
    p1, p2: vec2) -> [dynamic]struct{handle: int, dist: f32} {
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

get_map :: proc() -> Map {
    m: Map;
    return m;
}
/*
The key insight is push out on the shallowest overlap axis — if you're barely clipping a wall on the left but deeply overlapping on the top, you're hitting the side, not the top. Resolving the smaller overlap is almost always correct.
   */
entity_wall_collision :: proc(body, wall: ^rect) -> bool {
    // horizontal overlap
    if !raylib.CheckCollisionRecs(body^, wall^) do return false;

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
apply_camera :: proc(camera: rect, v: vec2) -> vec2 {
    return v - rect_pos(camera);
};
unapply_camera :: proc(camera: rect, v: vec2) -> vec2 {
    return v + rect_pos(camera);
};
