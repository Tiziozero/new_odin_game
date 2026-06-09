package main

import "vendor:raylib"
import "core:fmt"
import "core:slice"
import "project:common/game"
SortedDrawElement :: union {
    game.Entity,
    game.Drawable
}
get_sde_rect :: proc(a: SortedDrawElement) -> raylib.Rectangle {
    switch b in a {
    case game.Entity: return b.body;
    case game.Drawable: return {}
    case: panic("Impl")
    }
}
draw_sde :: proc(s: ^State, a: SortedDrawElement) {
    switch b in a {
    case game.Entity: e := b; draw_entity(s, s.camera, &e)
    case game.Drawable: draw_drawable(s, b)
    case: panic("Impl")
    }
}
draw_game :: proc(s: ^State, pref: game.Entity, buf: ^[dynamic]SortedDrawElement) {
    chunks := get_relevant_chuncks(s, pref)
    draw_map_floor(s, pref, chunks[:])
    draw_ordered_elements(s, pref, chunks[:], buf)
}
draw_ordered_elements :: proc(s: ^State, pref: game.Entity, chunks:[]game.v2i, buf: ^[dynamic]SortedDrawElement) {
    // draw entities
    for _, e in s.current_entities {
        append(buf, SortedDrawElement(e))
    }
    for id,k in chunks {
        c := game.map_get_chunk(&s.gmap, id)
        for t in c.drawables {
            append(buf, SortedDrawElement(t))
        }
    }
    slice.sort_by(buf[:], proc(a, b: SortedDrawElement) -> bool {
        ab := get_sde_rect(a);
        bb := get_sde_rect(b);
        return ab.y + ab.height < bb.y + bb.height
    })
    for &e in buf {
        draw_sde(s, e)
    }
    clear_dynamic_array(buf)
}


get_relevant_chuncks :: proc(s: ^State, pref: game.Entity) -> [dynamic]game.v2i { 
    x := pref.body.x / f32(game.CHUNK_SIDE_SIZE)
    y := pref.body.y / f32(game.CHUNK_SIDE_SIZE)
    x_i := int(x)
    y_i := int(y)
    chunks := make([dynamic]game.v2i,allocator=s.frame_arena.block_allocator);
    if x > 0 {
        for x in -1 ..= 1 {
            if y > 0 {
                for y in -1 ..= 1 {
                    cid := game.v2i{x_i + x, y_i + y}
                    c := game.map_get_chunk(&s.gmap, cid)
                    append(&chunks, cid);
                }
            } else {
                for y in -2 ..= 0 {
                    cid := game.v2i{x_i + x, y_i + y}
                    c := game.map_get_chunk(&s.gmap, cid)
                    append(&chunks, cid);
                }
            }
        }
    } else {
        for x in -2 ..= 0 {
            if y > 0 {
                for y in -1 ..= 1 {
                    cid := game.v2i{x_i + x, y_i + y}
                    c := game.map_get_chunk(&s.gmap, cid)
                    append(&chunks, cid);
                }
            } else {
                for y in -2 ..= 0 {
                    cid := game.v2i{x_i + x, y_i + y}
                    c := game.map_get_chunk(&s.gmap, cid)
                    append(&chunks, cid);
                }
            }
        }
    }
    return chunks;
}

draw_map_floor :: proc(s: ^State, pref: game.Entity, chunks: []game.v2i) { 
    for id,k in chunks {
        c := game.map_get_chunk(&s.gmap, id)
        draw_chunk_floor(s, c.cid, c)
    }

}
get_drawable_rect :: proc(d: game.Drawable) -> raylib.Rectangle {
    switch b in d {
    case game.WallDrawable: return b.rect
    case game.RockDrawable: return {}
    case: panic("Impl")
    }
}

draw_drawable :: proc(s: ^State, d: game.Drawable) {
    switch w in d {
    case game.WallDrawable:
        b := apply_camera(s.camera, game.rect_pos(w.rect));
           draw_sprite_src_rect(s, tiles, src = w.src_rect,
               body = {b.x, b.y, w.width, w.height})
           /* draw_text_center(s,get_ts_src_for_wall({}, w.wall_neighbours),
               b+0.5*game.rect_size(w.rect),tint=raylib.WHITE);*/
    case game.RockDrawable:
        b := apply_camera(s.camera, game.rect_pos(w.rect));
           draw_sprite_src_rect(s, tiles, src = w.src_rect,
               body = {b.x, b.y, w.width, w.height})
    case: panic("Impl")
    }
}
draw_chunk_floor :: proc(s: ^State, cid: game.v2i, c: ^game.Chunk) {
    for i in 0 ..< game.CHUNK_SIZE {     // rows/y
        for j in 0 ..< game.CHUNK_SIZE {     // cols/x
             // position
            p := raylib.Vector2{}
            p.x = f32(game.TILES_SIZE * (cid.x * game.CHUNK_SIZE + i))
            p.y = f32(game.TILES_SIZE * (cid.y * game.CHUNK_SIZE + j))
            p = apply_camera(s.camera, p) // cast to screen pos
            b := raylib.Vector2{game.TILES_SIZE, game.TILES_SIZE}
            t := c.tiles[j][i]
            draw_sprite_src_rect(s, tiles, src = t.src_rect, body = {p.x, p.y, b.x, b.y})
            /* 
            index := int(t.elevation * 10)
            str := fmt.aprintf("%d", index, allocator = s.frame_arena.block_allocator)
            draw_text_center(
                s,
                str,
                pos = {p.x + game.TILES_SIZE / 2, p.y + game.TILES_SIZE / 2},
                size = 20,
            ) */
        }
    }
}
