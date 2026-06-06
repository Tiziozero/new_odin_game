package game
import "core:fmt"
import "core:math/rand"
import "vendor:raylib"
MapItem :: struct {
}

v2i :: struct { x, y: int }
Map :: struct {
    items: [dynamic]MapItem,
    chunks: map[v2i]Chunk,
    seed: int,
    octaves: int,
}
WallNeighbour :: enum u8 { North, South, East, West }
WallNeighbours :: bit_set[WallNeighbour; u8]

Tile :: struct {
    n: u16,
    wall_neighbours: WallNeighbours, // only meaningful if this tile is a wall
    src_rect: raylib.Rectangle,
}
CHUNK_SIZE :: 32
TILES_SIZE :: 32
CHUNK_GEN_POS_FACTOR :: 12
CHUNK_SIDE_SIZE :: CHUNK_SIZE*TILES_SIZE
Chunk :: struct {
    tiles: [CHUNK_SIZE][CHUNK_SIZE]Tile,
    collidables: [dynamic]raylib.Rectangle,
}
generate_chunck :: proc(m: ^Map, x, y: int) -> Chunk {
    tile_x := x * CHUNK_SIZE
    tile_y := y * CHUNK_SIZE
    chunk := Chunk{}
    chunk.collidables = make([dynamic]raylib.Rectangle)
    for i in 0..<CHUNK_SIZE { // col
        for j in 0..<CHUNK_SIZE { // row
            t := Tile{}
            c := tile_index_at(m, tile_x+i, tile_y+j);
            t.n = c
            if c >= 7 {
                append(&chunk.collidables, raylib.Rectangle{
                    x=f32((tile_x + i)*TILES_SIZE),
                    y=f32((tile_y + j)*TILES_SIZE),
                    width=TILES_SIZE,
                    height=TILES_SIZE,
                })
                t.wall_neighbours = wall_neighbours_for(m,tile_x + i, tile_y + j)
            }
            t.src_rect = get_ts_src_for_tile(t)
            chunk.tiles[j][i] = t;
            // fmt.println(f, c, c>=7);
        }
    }
    m.chunks[v2i{x,y}] = chunk;
    return chunk
}
all4 := raylib.Rectangle{3*16, 0, 16, 15}
ltr := raylib.Rectangle{0, 0, 16, 15}
rt := raylib.Rectangle{16 ,0, 16, 15}
lt := raylib.Rectangle{2*16, 0, 16, 15}
grount_t_1 := raylib.Rectangle{0, 16, 16, 15}
grount_t_2 := raylib.Rectangle{1*16, 16, 16, 15}
grount_t_3 := raylib.Rectangle{2*16, 16, 16, 15}
grount_t_4 := raylib.Rectangle{3*16, 16, 16, 15}
random_ground_tile :: proc() -> raylib.Rectangle {
    switch rand.int31() % 4 {
    case 0: return grount_t_1
    case 1: return grount_t_2
    case 2: return grount_t_3
    case : return grount_t_4
    }
}
get_ts_src_for_tile ::  proc(t: Tile) -> raylib.Rectangle {
    if tile_is_wall(t.n) {
        switch t.wall_neighbours {
        case {.West,.East}:fallthrough
        case {.North,.West,.East}:
            return ltr
        case {.East}:fallthrough
        case {.North,.East}:
            return rt
        case {.West}:fallthrough
        case {.North,.West}:
            return lt
        case: return all4
        }
    }
    return random_ground_tile()
}
map_get_chunk :: proc(m :^Map, i: v2i) -> ^Chunk {
    c, ok := &m.chunks[i];
    if !ok {
        fmt.println("generating chunk:", i)
        new := generate_chunck(m, i.x,i.y)
        m.chunks[i] = new
        c = &m.chunks[i]
    }
    return c;
}
tile_index_at :: proc(m: ^Map, tile_x, tile_y: int) -> u16 {
    f := seeded_fbm(
        f32(tile_x) / CHUNK_GEN_POS_FACTOR,
        f32(tile_y) / CHUNK_GEN_POS_FACTOR,
        m.octaves, m.seed)
    return u16(10 * 0.5 * (f + 1))
}
tile_is_wall :: proc(index: u16) -> bool {
    return index >= 7
}
wall_neighbours_for :: proc(m: ^Map, tile_x, tile_y: int) -> WallNeighbours {
    neighbours := WallNeighbours{}

    if tile_is_wall(tile_index_at(m, tile_x, tile_y - 1)) { neighbours += {.North} }
    if tile_is_wall(tile_index_at(m, tile_x, tile_y + 1)) { neighbours += {.South} }
    if tile_is_wall(tile_index_at(m, tile_x - 1, tile_y)) { neighbours += {.West}  }
    if tile_is_wall(tile_index_at(m, tile_x + 1, tile_y)) { neighbours += {.East}  }

    return neighbours
}
