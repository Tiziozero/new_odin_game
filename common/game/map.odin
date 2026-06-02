package game
import "core:fmt"
MapItem :: struct {
}

v2i :: struct { x, y: int }
Map :: struct {
    items: [dynamic]MapItem,
    chunks: map[v2i]Chunk,
    seed: int,
    octaves: int,
}
Tile :: struct {
    collidable: bool,
    tileset_index: u16,
}
CHUNK_SIZE :: 32
TILES_SIZE :: 32
CHUNK_GEN_POS_FACTOR :: 12
CHUNK_SIDE_SIZE :: CHUNK_SIZE*TILES_SIZE
Chunk :: struct {
    tiles: [CHUNK_SIZE][CHUNK_SIZE]Tile,
}
generate_chunck :: proc(m: ^Map, x, y: int) -> Chunk {
    tile_x := x * CHUNK_SIZE
    tile_y := y * CHUNK_SIZE
    chunk := Chunk{}
    for i in 0..<CHUNK_SIZE {
        for j in 0..<CHUNK_SIZE {
            t := Tile{}
            f := seeded_fbm(
                       f32(tile_x + i)/CHUNK_GEN_POS_FACTOR,
                       f32(tile_y + j)/CHUNK_GEN_POS_FACTOR, m.octaves, m.seed)
            c := u16(10*0.5*(f + 1));
            t.tileset_index = c
            t.collidable = c >= 7
            chunk.tiles[j][i] = t;
            // fmt.println(f, c, c>=7);
        }
    }
    m.chunks[v2i{x,y}] = chunk;
    return chunk
}
map_get_chunk :: proc(m :^Map, i: v2i) -> Chunk {
    c, ok := m.chunks[i];
    if !ok {
        fmt.println("generating chunk:", i)
        c = generate_chunck(m, i.x,i.y)
        m.chunks[i] = c
    }
    return c;
}
