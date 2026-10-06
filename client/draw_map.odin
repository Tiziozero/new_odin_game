package main

import "core:math"
import "core:slice"
import "vendor:raylib"
import "project:common/game"

SortedDrawElement :: union {
    game.Entity,
    game.Drawable,
}

get_drawable_rect :: proc(d: game.Drawable) -> raylib.Rectangle {
    switch b in d {
    case game.WallDrawable: return b.rect
    case game.RockDrawable: return b.rect
    case: panic("Impl")
    }
}

get_sde_rect :: proc(a: SortedDrawElement) -> raylib.Rectangle {
    switch b in a {
    case game.Entity:   return b.body
    case game.Drawable: return get_drawable_rect(b)
    case: panic("Impl")
    }
}

// y-sort by bottom edge; x as tie-break so the order is deterministic
// (map iteration order of entities is not, and sort_by is not stable).
sde_less :: proc(a, b: SortedDrawElement) -> bool {
    ar, br := get_sde_rect(a), get_sde_rect(b)
    ay, by := ar.y + ar.height, br.y + br.height
    if ay != by { return ay < by }
    return ar.x < br.x
}

draw_sde :: proc(s: ^State, a: ^SortedDrawElement) {
    switch &b in a^ {
    case game.Entity:   draw_entity(s, s.camera, &b)
    case game.Drawable: draw_drawable(s, b)
    case: panic("Impl")
    }
}

// ---- frame ------------------------------------------------------------------

// Three queues, three loops:
//   Terrain  - opaque ground tiles
//   Effects  - water shader, (later) moving grass; drawn under entities
//   Objects  - entities + walls/rocks, y-sorted
draw_game :: proc(s: ^State, pref: game.Entity, buf: ^[dynamic]SortedDrawElement) {
    chunks := get_relevant_chuncks(s, pref)

    s.layer = .Terrain
    draw_terrain(s, chunks[:])

    s.layer = .Effects
    draw_effects(s, chunks[:])

    s.layer = .Objects
    draw_ordered_elements(s, chunks[:], buf)
}

draw_terrain :: proc(s: ^State, chunks: []game.v2i) {
    view := logical_view()
    for id in chunks {
        draw_chunk_floor(s, game.map_get_chunk(&s.gmap, id), view)
    }
}

draw_effects :: proc(s: ^State, chunks: []game.v2i) {
    view := logical_view()
    water_tiles := 0
    for id in chunks {
        water_tiles += draw_chunk_water(s, game.map_get_chunk(&s.gmap, id), view)
    }
    slog(s, "water tiles on screen: %d", water_tiles)
    // grass / other under-entity effects go here
}

draw_ordered_elements :: proc(s: ^State, chunks: []game.v2i, buf: ^[dynamic]SortedDrawElement) {
    view := logical_view()
    for _, e in s.current_entities {
        append(buf, SortedDrawElement(e))
    }
    for id in chunks {
        c := game.map_get_chunk(&s.gmap, id)
        for d in c.drawables {
            if rect_on_view(s, get_drawable_rect(d), view) {
                append(buf, SortedDrawElement(d))
            }
        }
    }
    slice.sort_by(buf[:], sde_less)
    for &e in buf {
        draw_sde(s, &e)
    }
    clear(buf)
}

// ---- chunks -----------------------------------------------------------------

// 3x3 chunks around the player. floor (not int()) so negative coordinates and
// exact multiples of the chunk size land in the right chunk.
// Generation happens here, in one place, before anything draws.
get_relevant_chuncks :: proc(s: ^State, pref: game.Entity) -> [dynamic]game.v2i {
    cx := int(math.floor(pref.body.x / f32(game.CHUNK_SIDE_SIZE)))
    cy := int(math.floor(pref.body.y / f32(game.CHUNK_SIDE_SIZE)))
    chunks := make([dynamic]game.v2i, 0, 9, frame_allocator(s))
    for dy in -1 ..= 1 {
        for dx in -1 ..= 1 {
            cid := game.v2i{cx + dx, cy + dy}
            _ = game.map_get_chunk(&s.gmap, cid)
            append(&chunks, cid)
        }
    }
    return chunks
}

rect_on_view :: proc(s: ^State, r: raylib.Rectangle, view: raylib.Rectangle) -> bool {
    p := apply_camera(s.camera, game.rect_pos(r))
    return rect_overlaps({p.x, p.y, r.width, r.height}, view)
}

// ---- drawing ----------------------------------------------------------------

draw_drawable :: proc(s: ^State, d: game.Drawable) {
    r:   raylib.Rectangle
    src: raylib.Rectangle
    switch w in d {
    case game.WallDrawable: r, src = w.rect, w.src_rect
    case game.RockDrawable: r, src = w.rect, w.src_rect
    case: panic("Impl")
    }
    p := apply_camera(s.camera, game.rect_pos(r))
    draw_sprite_src_rect(s, tiles, src = src, body = {p.x, p.y, r.width, r.height})
}

// Every tile, water included (water gets its static look here and the animated
// overlay in draw_chunk_water).
draw_chunk_floor :: proc(s: ^State, c: ^game.Chunk, view: raylib.Rectangle) {
    for j in 0 ..< game.CHUNK_SIZE {         // row / y
        for i in 0 ..< game.CHUNK_SIZE {     // col / x
            t := &c.tiles[j][i]
            p := apply_camera(s.camera, raylib.Vector2{t.x, t.y})
            body := raylib.Rectangle{p.x, p.y, game.TILES_SIZE, game.TILES_SIZE}
            if !rect_overlaps(body, view) { continue }
            draw_sprite_src_rect(s, tiles, src = t.src_rect, body = body)
        }
    }
}

// Water tiles only, drawn through the water shader.
draw_chunk_water :: proc(s: ^State, c: ^game.Chunk, view: raylib.Rectangle) -> (drawn: int) {
    for j in 0 ..< game.CHUNK_SIZE {
        for i in 0 ..< game.CHUNK_SIZE {
            t := &c.tiles[j][i]
            if t.biom != .Water { continue }
            p := apply_camera(s.camera, raylib.Vector2{t.x, t.y})
            body := raylib.Rectangle{p.x, p.y, game.TILES_SIZE, game.TILES_SIZE}
            if !rect_overlaps(body, view) { continue }
            draw_sprite_src_rect(s, tiles, src = t.src_rect, body = body, effect = .Water)
            drawn += 1
        }
    }
    return
}
