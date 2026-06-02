package game
CELLS := 80;
import "core:strings"

import "core:os"
import "core:fmt"
import "vendor:raylib" 
import "project:common/buffer_io"


USR_MSG_MOVE:: 1;

SCREEN_SIZE :: raylib.Vector2{1200,900}

EntityDelta :: struct {
    body: raylib.Rectangle,
    status: EntityStatus,
    texture: u32,
}

pack_entity :: proc(buf: ^buffer_io.Buffer, e: ^EntityDelta) {
    buffer_io.buffer_write_u32(buf, transmute(u32)e.status);
    buffer_io.buffer_write_f32(buf, e.body.x);
    buffer_io.buffer_write_f32(buf, e.body.y);
    buffer_io.buffer_write_f32(buf, e.body.width);
    buffer_io.buffer_write_f32(buf, e.body.height);
    buffer_io.buffer_write_u32(buf, transmute(u32)e.texture);
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
    status: EntityStatus,
    handle: EntityHandle,
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
        } 
        am.assets[i] = Asset {
            img = k.img,
            name = k.name,
            height = k.height,
            width = k.width,
            texture = t,
        }
        fmt.println("freeing", k.img);
        // delete(cstr)
        fmt.println("freed", k.img);
    }
    return am
}
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
