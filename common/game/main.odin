package game
CELLS := 80;
ENTITY_SPEED :: 80
import "core:strings"

import "core:os"
import "core:fmt"
import "vendor:raylib" 
import "project:common/buffer_io"
ABILITIES_COUNT :: 6


SCREEN_SIZE :: raylib.Vector2{1200,900}
EntityDeltaData :: u16 // each field, like position, status, texture and what not
EDD_POS ::      0b0001
EDD_STATUS ::   0b0010
EDD_TEXTURE ::  0b0100
EDD_HEALTH ::   0b1000
FULL_SYNC :: EDD_TEXTURE + EDD_STATUS + EDD_POS + EDD_HEALTH // lazy

EntityDelta :: struct {
    delta: EntityDeltaData,
    body: raylib.Rectangle,
    health: f32,
    status: EntityStatus,
    texture: u32,
}

// implement this
get_entity_delta :: proc(prev, cur: Entity, all:=false) -> EntityDelta {
    d := EntityDelta{}
    if prev.body != cur.body || all {
        d.delta |= EDD_POS
        d.body   = cur.body
    }
    if prev.status != cur.status || all {
        d.delta  |= EDD_STATUS
        d.status  = cur.status
    }
    if prev.texture != cur.texture || all {
        d.delta  |= EDD_TEXTURE
        d.texture = cur.texture
    }
    if prev.health != cur.health || all {
        d.delta  |= EDD_HEALTH
        d.health = cur.health
    }
    return d
}

implement_entity_delta :: proc(entity: ^Entity, delta: ^EntityDelta) {
    if delta.delta & EDD_POS    != 0 { entity.body      = delta.body    }
    if delta.delta & EDD_STATUS != 0 { entity.status    = delta.status  }
    if delta.delta & EDD_TEXTURE!= 0 { entity.texture   = delta.texture }
    if delta.delta & EDD_HEALTH != 0 { entity.health    = delta.health }
}

pack_entity :: proc(buf: ^buffer_io.Buffer, e: ^EntityDelta, all := false) {
    buffer_io.buffer_write_u16(buf, e.delta)
    if e.delta & EDD_POS != 0 {
        buffer_io.buffer_write_f32(buf, e.body.x)
        buffer_io.buffer_write_f32(buf, e.body.y)
        buffer_io.buffer_write_f32(buf, e.body.width)
        buffer_io.buffer_write_f32(buf, e.body.height)
    }
    if e.delta & EDD_STATUS != 0 {
        buffer_io.buffer_write_u32(buf, transmute(u32)e.status)
    }
    if e.delta & EDD_TEXTURE != 0 {
        buffer_io.buffer_write_u32(buf, e.texture)
    }
    if e.delta & EDD_HEALTH != 0 {
        buffer_io.buffer_write_f32(buf, e.health)
    }
}

unpack_entity :: proc(buf: ^buffer_io.Buffer, e: ^EntityDelta) {
    delta, ok := buffer_io.buffer_read_u16(buf)
    assert(ok)
    e.delta = delta
    if delta & EDD_POS != 0 {
        e.body.x,     ok = buffer_io.buffer_read_f32(buf); assert(ok)
        e.body.y,     ok = buffer_io.buffer_read_f32(buf); assert(ok)
        e.body.width, ok = buffer_io.buffer_read_f32(buf); assert(ok)
        e.body.height,ok = buffer_io.buffer_read_f32(buf); assert(ok)
    }
    if delta & EDD_STATUS != 0 {
        s, sok := buffer_io.buffer_read_u32(buf); assert(sok)
        e.status = transmute(EntityStatus)s
    }
    if delta & EDD_TEXTURE != 0 {
        e.texture, ok = buffer_io.buffer_read_u32(buf); assert(ok)
    }
    if delta & EDD_HEALTH != 0 {
        e.health, ok = buffer_io.buffer_read_f32(buf); assert(ok)
    }
}

// pack and unpack whats needed
old_pack_entity :: proc(buf: ^buffer_io.Buffer, e: ^EntityDelta) {
    buffer_io.buffer_write_u32(buf, transmute(u32)e.status);
    buffer_io.buffer_write_f32(buf, e.body.x);
    buffer_io.buffer_write_f32(buf, e.body.y);
    buffer_io.buffer_write_f32(buf, e.body.width);
    buffer_io.buffer_write_f32(buf, e.body.height);
    buffer_io.buffer_write_u32(buf, transmute(u32)e.texture);
}
old_unpack_entity :: proc(buf: ^buffer_io.Buffer, e: ^EntityDelta) {
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
    e.body.width, ok = buffer_io.buffer_read_f32(buf);
    if !ok {
        fmt.panicf("Failed to read u32\n");
    }
    e.body.height, ok= buffer_io.buffer_read_f32(buf);
    if !ok {
        fmt.panicf("Failed to read u32\n");
    }
    e.texture, ok = buffer_io.buffer_read_u32(buf);
    if !ok {
        fmt.panicf("Failed to read u32\n");
    }
}

rect_size :: proc(r: raylib.Rectangle) -> raylib.Vector2 {
    return raylib.Vector2{r.width, r.height};
}
rect_pos :: proc(r: raylib.Rectangle) -> raylib.Vector2 {
    return raylib.Vector2{r.x, r.y};
}

EntityStatus :: enum u32 {
    ESDEAD = 0,
    ESALIVE,
    ESDYING,
    ESON=ESALIVE,
};
EntityHandle :: u32;
Entity :: struct {
    health: f32,
    status: EntityStatus,
    texture: u32, // texture key for game.textures
    body: raylib.Rectangle,
    id: EntityHandle,
}
get_env :: proc(s: string) -> string {
    ret := os.get_env(s, context.allocator);
    fmt.printfln("-- got %s from get_env", ret);
    return ret;
}

import "core:io";
import "core:encoding/json"
AssetsConfig :: struct {
    img, name: string,
    width, height: int
}



Asset :: struct {
    texture: raylib.Texture2D,
    img, name: string,
    width, height: int
}
AssetManger :: struct {
    assets: []Asset,
}
load_assets :: proc(config_path: string, load:=false, allocator:=context.allocator) -> AssetManger {
    data, err := os.read_entire_file_from_path(config_path, context.allocator);
    if err != io.Error.None {
        panic("Failed to read file")
    }
    defer delete(data)

    config: []AssetsConfig

    merr := json.unmarshal(data, &config)
    if merr != nil {
        fmt.println(merr)
        panic("JSON error")
    }

    fmt.println(config)
    am := AssetManger{}
    fmt.println("Len assets config:", len(config))
    am.assets = make([]Asset, len(config));
    for k, i in config {
        fmt.println(i, "loading", k.img);
        cstr := strings.clone_to_cstring(k.img, allocator=allocator)
        t : raylib.Texture2D
        if load {
            t = raylib.LoadTexture(cstr);
            fmt.println("texture id for", cstr, ":", t.id)
        } 
        am.assets[i] = Asset {
            img = k.img,
            name = k.name,
            height = k.height,
            width = k.width,
            texture = t,
        }
    }
    return am
}
/*
The key insight is push out on the shallowest overlap axis — if you're barely clipping a wall on the left but deeply overlapping on the top, you're hitting the side, not the top. Resolving the smaller overlap is almost always correct.
   */
entity_wall_collision :: proc(body, wall: raylib.Rectangle) -> (raylib.Vector2,bool) {
    // horizontal overlap
    if !raylib.CheckCollisionRecs(body, wall) do return {},false;

    // compute overlap on each axis
    overlap_x := min(body.x + body.width,  wall.x + wall.width)  - max(body.x, wall.x)
    overlap_y := min(body.y + body.height, wall.y + wall.height) - max(body.y, wall.y)

    r := rect_pos(body)
    // push out on shallowest axis
    if overlap_x < overlap_y {
        if body.x < wall.x {
            r.x = body.x - overlap_x
        } else {
            r.x = body.x + overlap_x
        }
    } else {
        if body.y < wall.y {
            r.y = body.y - overlap_y
        } else {
            r.y = body.y + overlap_y
        }
    }
    return r, true;
}
// returns position to move to
check_entity_map_collisions :: proc (m: ^Map, entity: Entity) -> (raylib.Vector2, bool){
    // get entities map
    chunck_i_x := int(entity.body.x / CHUNK_SIDE_SIZE);
    chunck_i_y := int(entity.body.y / CHUNK_SIDE_SIZE);
    for x in -1..=1 {
        for y in -1..=1 {
            chunk_i := v2i{x=chunck_i_x+x, y=chunck_i_y+y};
             chunk := map_get_chunk(m, chunk_i)
             for t in chunk.collidables {
                 // make it so that it stops moving at collision with wall.
                 if v, ok := entity_wall_collision(entity.body, t); ok {
                     fmt.println(v)
                     return v, true
                 }
             }
        }
    }
    return {}, false
}
AbilityKind :: enum {
    Projectile,
    Mele,
    Spell,
}
EntityAbility :: struct {
    ability_id: u32, // indexes into game.abilities
    level: u32,
    cooldown, cooldown_time: f32, // current cooldown to cast again and it's cooldown
    upgrade_requirements: struct{}, // some other time
    active: bool,
}
// have projectiles be "spawn data + hit msg" for game to send to clients
// and clients predict movement.
Projectile :: struct {
    origin, direction, position: raylib.Vector2,
    active: bool, // is active
    // what kind and which individually
    projectile_id : u32, // what projectile
    id: u32, // which projectile
    owner: u32,
}
pack_projectile_spawn_data :: proc (p: Projectile, b: ^buffer_io.Buffer) {
    buffer_io.buffer_write_u32(b, p.id)
    buffer_io.buffer_write_u32(b, p.projectile_id)
    buffer_io.buffer_write_f32(b, p.origin.x)
    buffer_io.buffer_write_f32(b, p.origin.y)
    buffer_io.buffer_write_f32(b, p.direction.y)
    buffer_io.buffer_write_f32(b, p.direction.x)
    buffer_io.buffer_write_f32(b, p.position.x)
    buffer_io.buffer_write_f32(b, p.position.y)
}
unpack_projectile_spawn_data :: proc (b: ^buffer_io.Buffer) -> Projectile {
    ok: bool
    p: Projectile
    p.id, ok = buffer_io.buffer_read_u32(b); assert(ok)
    p.projectile_id, ok = buffer_io.buffer_read_u32(b); assert(ok)
    p.origin.x, ok = buffer_io.buffer_read_f32(b); assert(ok)
    p.origin.y, ok = buffer_io.buffer_read_f32(b); assert(ok)
    p.direction.x, ok = buffer_io.buffer_read_f32(b); assert(ok)
    p.direction.y, ok = buffer_io.buffer_read_f32(b); assert(ok)
    p.position.x, ok = buffer_io.buffer_read_f32(b); assert(ok)
    p.position.y, ok = buffer_io.buffer_read_f32(b); assert(ok)
    return p
}
