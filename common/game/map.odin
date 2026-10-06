package game
import "core:fmt"
import "core:mem"
import "vendor:raylib"
MapItem :: struct {
}

v2i :: struct { x, y: int }
Map :: struct {
    map_arena: mem.Dynamic_Arena,
    items: [dynamic]MapItem,
    // Chunks are ~64KB each and live behind a pointer: a ^Chunk handed out by
    // map_get_chunk stays valid even when generating another chunk grows the map.
    chunks: map[v2i]^Chunk,
    seed: int,
    octaves: int,
}
WallNeighbour :: enum u8 { North, South, East, West }
WallNeighbours :: bit_set[WallNeighbour; u8]

Biom :: enum {
    Water,
    Land,
    Mountain,
}

// One source of truth for the thresholds (biome and wall checks used to disagree at == 0.7).
WATER_ELEVATION :: 0.4
WALL_ELEVATION  :: 0.7

new_map :: proc(seed := 420, octaves := 8) -> Map {
    m := Map{}
    mem.dynamic_arena_init(&m.map_arena)
    m.chunks = make(map[v2i]^Chunk)
    m.seed = seed
    m.octaves = octaves
    return m
}
get_biom :: proc(elevation, moisture, temperature: f32) -> Biom {
    if elevation < WATER_ELEVATION { return .Water }
    if elevation >= WALL_ELEVATION { return .Mountain }
    return .Land
}
Tile :: struct {
    wall_neighbours: WallNeighbours,
    biom: Biom,
    occupied: bool,
    elevation, moisture, temp: f32,
    using rect: raylib.Rectangle,
    // wall_neighbours: WallNeighbours, // only meaningful if this tile is a wall
    src_rect: raylib.Rectangle,
}
Drawable :: union {
    WallDrawable,
    RockDrawable,
}
WallDrawable :: struct {
    wall_neighbours: WallNeighbours,
    using rect: raylib.Rectangle,
    src_rect: raylib.Rectangle,
}
RockDrawable :: struct {
    ts: int,
    src_rect: raylib.Rectangle,
    using rect: raylib.Rectangle,
}
Collidable :: struct {
    using rect: raylib.Rectangle,
}
CHUNK_SIZE :: 32
TILES_SIZE :: 32
CHUNK_GEN_POS_FACTOR :: 22
CHUNK_SIDE_SIZE :: CHUNK_SIZE*TILES_SIZE
Chunk :: struct {
    cid: v2i,
    tiles: [CHUNK_SIZE][CHUNK_SIZE]Tile,
    collidables: [dynamic]Collidable,
    drawables: [dynamic]Drawable,
}
generate_chunck :: proc(m: ^Map, x, y: int) {
    // (the old |x|,|y| > 10 panics are gone: the noise is infinite, and the
    // draw code asks for the neighbours of the player's chunk, so walking to
    // the edge of the old limit would have crashed the game.)
    alloc := mem.dynamic_arena_allocator(&m.map_arena)
    tile_x := x * CHUNK_SIZE
    tile_y := y * CHUNK_SIZE
    chunk := new(Chunk, alloc)
    chunk.cid = {x, y}
    chunk.collidables = make([dynamic]Collidable, 0, 64, alloc)
    chunk.drawables   = make([dynamic]Drawable, 0, 128, alloc)
    for j in 0..<CHUNK_SIZE { // row/y
        for i in 0..<CHUNK_SIZE { // col/x
            wx := tile_x + i
            wy := tile_y + j
            px := f32(wx * TILES_SIZE)
            py := f32(wy * TILES_SIZE)
            trect := raylib.Rectangle{
                x=px, y=py, width=TILES_SIZE, height=TILES_SIZE,
            }
            t := Tile{}
            t.rect = trect
            t.elevation = tile_elevation(m, wx, wy)
            t.temp = tile_temp(m, wx, wy)
            t.moisture = tile_moisture(m, wx, wy)
            if tile_is_wall(t.elevation) {
                t.wall_neighbours = wall_neighbours_for(m, wx, wy)
                append(&chunk.collidables, Collidable{
                    rect=trect,
                })
                t.occupied=true
                append(&chunk.drawables, WallDrawable{
                    rect=trect,
                    wall_neighbours=t.wall_neighbours,
                    src_rect = get_ts_src_for_wall({x=px,y=py}, t.wall_neighbours),
                })
            }
            t.biom = get_biom(t.elevation, t.moisture, t.temp)
            t.src_rect = get_ts_src_for_tile(t)
            chunk.tiles[j][i] = t
        }
    }
    gen_chunk_items(m, chunk)
    m.chunks[v2i{x,y}] = chunk
}
chunk_rand :: proc(cid: v2i, salt: int) -> int {
    h := u32(2166136261) // FNV offset basis
    h ~= u32(cid.x) * 0x85ebca6b
    h ~= u32(cid.y) * 0xc2b2ae35
    h ~= u32(salt)  * 0x7feb352d
    h ~= h >> 16
    h *= 0x45d9f3b
    h ~= h >> 16
    return int(h)
}
new_random_map_item :: proc(m: ^Map, c: ^Chunk, x, y: int) {
    wx := c.cid.x*CHUNK_SIZE + x
    wy := c.cid.y*CHUNK_SIZE + y
    item := RockDrawable{}
    // was fbm at integer coords with seed*x*y: constant for gradient noise, and
    // seed 0 whenever x or y was 0. A hash of the world tile is what's wanted here.
    item.src_rect = rock if tile_hash(wx, wy, m.seed) % 2 == 0 else rock_2
    item.x = f32(wx * TILES_SIZE)
    item.y = f32(wy * TILES_SIZE)
    item.width = TILES_SIZE
    item.height = TILES_SIZE
    append(&c.drawables, item)
    c_rect := Collidable{rect=item.rect}
    append(&c.collidables, c_rect)
}
gen_chunk_items :: proc(m: ^Map, c: ^Chunk) {
    // +0.5: sampling noise exactly on integer lattice points tends to return a flat value
    density := fbm_xyos(f32(c.cid.x) + 0.5, f32(c.cid.y) + 0.5, m.octaves, m.seed)
    count := int(20 * density)
    for i in 0..<count {
        for k in 0..<20 {
            // salt includes k: retrying used to roll the exact same tile every time
            x := chunk_rand(c.cid, 67 * (i + 1) + 1000 * k) % CHUNK_SIZE
            y := chunk_rand(c.cid, 69 * (i + 1) + 1000 * k) % CHUNK_SIZE
            tile := &c.tiles[y][x]
            if tile.occupied || tile.biom == .Water { continue }
            tile.occupied = true // so two rocks can't share a tile
            new_random_map_item(m, c, x, y)
            break
        }
    }
}

// Atlas rects. Renamed from ltr/lt/rt/t: a package-level `t` is begging to be shadowed.
wall_ltr := raylib.Rectangle{0, 0, 16, 16}
wall_lt  := raylib.Rectangle{16 ,0, 16, 16}
wall_rt  := raylib.Rectangle{2*16, 0, 16, 16}
wall_top := raylib.Rectangle{3*16, 0, 16, 16}
grount_t_1 := raylib.Rectangle{0, 16, 16, 16}
grount_t_2 := raylib.Rectangle{1*16, 16, 16, 16}
grount_t_3 := raylib.Rectangle{2*16, 16, 16, 16}
grount_t_4 := raylib.Rectangle{3*16, 16, 16, 16}
trbl_1 := raylib.Rectangle{0*16, 2*16, 16, 16}
trbl_2 := raylib.Rectangle{1*16, 2*16, 16, 16}
trbl_3 := raylib.Rectangle{2*16, 2*16, 16, 16}
trbl_4 := raylib.Rectangle{3*16, 2*16, 16, 16}
snow_1 := raylib.Rectangle{0*16, 3*16, 16, 16}
snow_2 := raylib.Rectangle{1*16, 3*16, 16, 16}
snow_3 := raylib.Rectangle{2*16, 3*16, 16, 16}
snow_4 := raylib.Rectangle{3*16, 3*16, 16, 16}
water_1 := raylib.Rectangle{0*16, 4*16, 16, 16}
water_2 := raylib.Rectangle{1*16, 4*16, 16, 16}
water_3 := raylib.Rectangle{2*16, 4*16, 16, 16}
water_4 := raylib.Rectangle{3*16, 4*16, 16, 16}
water_11 := raylib.Rectangle{0*16, 5*16, 16, 16}
water_12 := raylib.Rectangle{1*16, 5*16, 16, 16}
water_13 := raylib.Rectangle{2*16, 5*16, 16, 16}
water_14 := raylib.Rectangle{3*16, 5*16, 16, 16}
// TODO(check atlas): water_21..24 are byte-for-byte copies of water_11..14 (row 5).
// If they were meant to be row 6, change the y here; I left it since I can't see the atlas.
water_21 := raylib.Rectangle{0*16, 5*16, 16, 16}
water_22 := raylib.Rectangle{1*16, 5*16, 16, 16}
water_23 := raylib.Rectangle{2*16, 5*16, 16, 16}
water_24 := raylib.Rectangle{3*16, 5*16, 16, 16}
rock := raylib.Rectangle{0, 112, 16,16}
rock_2 := raylib.Rectangle{16, 112, 16,16}
tile_hash :: proc(x, y, seed: int) -> u32 {
    itseed := 420 + 2;
    h := u32(itseed)
    h ~= u32(x) * 0x85ebca6b
    h ~= u32(y) * 0xc2b2ae35

    h ~= h >> 16
    h *= 0x7feb352d
    h ~= h >> 15
    h *= 0x846ca68b
    h ~= h >> 16

    return h
}

// NOTE: 10 variants -> x offsets up to 9*16, but only grount_t_1..4 (4 columns) are
// declared above. Fine if the atlas row really has 10 tiles; otherwise use % 4.
random_ground_tile :: proc(x,y,s:int) -> raylib.Rectangle {
    return { f32(tile_hash(x, y, s) % 10) * 16, 16, 16, 16 }
}
random_snow_tile :: proc(x,y,s:int) -> raylib.Rectangle {
    switch tile_hash(x, y, s) % 4 {
    case 0: return  snow_1
    case 1: return  snow_2
    case 2: return  snow_3
    case : return   snow_4
    }
}
random_water_tile :: proc(x,y,s:int) -> raylib.Rectangle {
    switch tile_hash(x, y, s) % 12 {
    case 0: return      water_1
    case 1: return      water_2
    case 2: return      water_3
    case 3: return      water_4
    case 4: return      water_11
    case 5: return      water_12
    case 6: return      water_13
    case 7: return      water_14
    case 8: return      water_21
    case 9: return      water_22
    case 10: return     water_23
    case 11: return     water_24
    case : return       water_4
    }
}
random_trbl_tile :: proc(x,y,s:int) -> raylib.Rectangle {
    switch tile_hash(x,y,s) % 4 {
    case 0: return  trbl_1
    case 1: return  trbl_2
    case 2: return  trbl_3
    case : return   trbl_4
    }
}
get_ts_src_for_tile ::  proc(t: Tile) -> raylib.Rectangle {
    switch t.biom {
    case .Mountain: {
        return random_snow_tile(int(t.x),int(t.y),5)
    }
    case .Land: {
        return random_ground_tile(int(t.x),int(t.y),8)
    }
    case .Water: {
        return random_water_tile(int(t.x),int(t.y),10)
    }
    case: panic("What")
    }
}
get_ts_src_for_wall :: proc(_t:Tile, n: WallNeighbours) ->raylib.Rectangle {
    if .South in n { return random_trbl_tile(int(_t.x),int(_t.y),9) }
    switch n {
    case {.West,.East}:fallthrough
    case {.North,.West,.East}:
        return wall_ltr
    case {.East}:fallthrough
    case {.North,.East}:
        return wall_lt
    case {.West}:fallthrough
    case {.North,.West}:
        return wall_rt
    case {.North}: fallthrough
    case {}: return wall_top
    case: fmt.println(n); panic("handle case for walls");
    }
    fmt.println(n);
    panic("What");
}
map_get_chunk :: proc(m :^Map, i: v2i) -> ^Chunk {
    if c, ok := m.chunks[i]; ok {
        return c
    }
    fmt.println("generating chunk:", i)
    generate_chunck(m, i.x, i.y)
    return m.chunks[i]
}
tile_elevation :: proc(m: ^Map, tile_x, tile_y: int) -> f32 {
    f := fbm_xyos(
        f32(tile_x) / CHUNK_GEN_POS_FACTOR,
        f32(tile_y) / CHUNK_GEN_POS_FACTOR,
        m.octaves, m.seed)
    return f
}
tile_moisture :: proc(m: ^Map, tile_x, tile_y: int) -> f32 {
    f := fbm_xyos(
        f32(tile_x) / CHUNK_GEN_POS_FACTOR/ 20,
        f32(tile_y) / CHUNK_GEN_POS_FACTOR/ 20,
        m.octaves, m.seed)
    return 1-f
}
tile_temp :: proc(m: ^Map, tile_x, tile_y: int) -> f32 {
    f := fbm_xyos(
        f32(tile_x) / CHUNK_GEN_POS_FACTOR/100,
        f32(tile_y) / CHUNK_GEN_POS_FACTOR/100,
        1, m.seed + 474627);
    return f;
}

fbm_xyos :: proc(x,y: f32, o, s: int) -> f32 {
    return 0.5*(seeded_fbm(x, y, o, s)+1)
}
tile_is_wall :: proc(index: f32) -> bool {
    return index >= WALL_ELEVATION
}
// Perf note: this re-samples 8-octave noise 4x per wall tile; if chunk generation
// hitches, compute the elevations for the chunk (+1 tile border) once and reuse them.
wall_neighbours_for :: proc(m: ^Map, tile_x, tile_y: int) -> WallNeighbours {
    neighbours := WallNeighbours{}

    if tile_is_wall(tile_elevation(m, tile_x, tile_y - 1)) { neighbours += {.North} }
    if tile_is_wall(tile_elevation(m, tile_x, tile_y + 1)) { neighbours += {.South} }
    if tile_is_wall(tile_elevation(m, tile_x - 1, tile_y)) { neighbours += {.West}  }
    if tile_is_wall(tile_elevation(m, tile_x + 1, tile_y)) { neighbours += {.East}  }

    return neighbours
}
