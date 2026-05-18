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

SCREEN_SIZE :: raylib.Vector2{1200,900}

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
EntityHandle :: int;
Entity :: struct {
    status: EntityStatus,
    handle: EntityHandle,
    texture: int, // texture key for game.textures
    body: raylib.Rectangle,
}
get_env :: proc(s: string) -> string {
    ret := os.get_env(s, context.allocator);
    fmt.printfln("-- got %s from get_env", ret);
    return ret;
}

entity_new :: proc(txt_handle: int, x, y, w, h: f32) -> Entity {
    e : Entity;
    e.texture = txt_handle;
    e.body.x = x;
    e.body.y = y;
    e.body.width = w;
    e.body.height = h;
    return e;
};
/*
The key insight is push out on the shallowest overlap axis — if you're barely clipping a wall on the left but deeply overlapping on the top, you're hitting the side, not the top. Resolving the smaller overlap is almost always correct.
   */
entity_wall_collision :: proc(body, wall: ^raylib.Rectangle) -> bool {
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
