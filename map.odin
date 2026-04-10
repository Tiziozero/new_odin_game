package main

import "vendor:raylib"
import "core:fmt"
CHUNK_SIZE :: 8;
// CHUNK_SIZE by CHUNK_SIZE chunks
MapChunk :: struct {
    tiles: [CHUNK_SIZE*CHUNK_SIZE]Tile,
    walls: [dynamic]Wall,
}

// cx/cy, chunk index x and y, so like, not tiles, but every CHUNK_SIZE tiles
gen_chunck :: proc(m: ^Map, cx, cy: int) -> MapChunk {
    fmt.println("generating chunk:", cx, cy);
    c: MapChunk;
    for x in 0..<CHUNK_SIZE {
        for y in 0..<CHUNK_SIZE {
            t: Tile;
            r := fbm(f32(cx*CHUNK_SIZE+x)*0.05, f32(cy*CHUNK_SIZE+y)*0.05, 5);
       r = (r + 1.0) * 0.5
            if r < 0.2 {
                t.c = 0
            } else if r < 0.5 {
                t.c = 1
            } else {
                t.c = 2
            };
            if r > 0.8 {
                w: Wall;
                w.body.x = f32(cx*CHUNK_SIZE*CELLS+x*CELLS);
                w.body.y = f32(cy*CHUNK_SIZE*CELLS+y*CELLS);
                w.body.width = f32(CELLS);
                w.body.height = f32(CELLS);
                w.color = raylib.BLACK;
                fmt.printfln("gen wall at", w.body);
                append(&c.walls, w);
            }
            c.tiles[y*CHUNK_SIZE+x] = t;
        }
    }
    return c;
}
