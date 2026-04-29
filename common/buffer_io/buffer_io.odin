package buffer_io

import "core:mem"

Buffer :: struct {
    data:   []byte,
    pos:    int,
    len:    int,
    cap:    int,
}

buffer_make :: proc(cap: int, allocator := context.allocator) -> Buffer {
    return Buffer{
        data = make([]byte, cap, allocator),
        pos  = 0,
        len  = 0,
        cap  = cap,
    }
}

buffer_destroy :: proc(buf: ^Buffer, allocator := context.allocator) {
    delete(buf.data, allocator)
    buf^ = {}
}

buffer_reset :: proc(buf: ^Buffer) {
    buf.pos = 0
    buf.len = 0
}

// ── Write ────────────────────────────────────────────────────────────────────

buffer_write_bytes :: proc(buf: ^Buffer, src: []byte) -> (n: int, ok: bool) {
    space := buf.cap - buf.len
    if len(src) > space do return 0, false
    copy(buf.data[buf.len:], src)
    buf.len += len(src)
    return len(src), true
}

buffer_write :: proc(buf: ^Buffer, v: $T) -> bool {
    size :: size_of(T)
    if buf.len + size > buf.cap do return false
    local := v
    dest  := buf.data[buf.len : buf.len + size]
    src   := mem.ptr_to_bytes(&local, size)
    copy(dest, src)
    buf.len += size
    return true
}

// ── Read ─────────────────────────────────────────────────────────────────────

buffer_read_bytes :: proc(buf: ^Buffer, n: int) -> (data: []byte, ok: bool) {
    if buf.pos + n > buf.len do return nil, false
    data = buf.data[buf.pos : buf.pos + n]
    buf.pos += n
    return data, true
}

buffer_read :: proc(buf: ^Buffer, $T: typeid) -> (v: T, ok: bool) {
    size :: size_of(T)
    if buf.pos + size > buf.len do return {}, false
    mem.copy(&v, &buf.data[buf.pos], size)
    buf.pos += size
    return v, true
}

// ── Peek (read without advancing pos) ────────────────────────────────────────

buffer_peek :: proc(buf: ^Buffer, $T: typeid) -> (v: T, ok: bool) {
    size :: size_of(T)
    if buf.pos + size > buf.len do return {}, false
    mem.copy(&v, &buf.data[buf.pos], size)
    return v, true
}

buffer_remaining :: proc(buf: ^Buffer) -> int { return buf.len - buf.pos }
buffer_written   :: proc(buf: ^Buffer) -> int { return buf.len }

// ── Write integers ────────────────────────────────────────────────────────────

buffer_write_u8  :: proc(buf: ^Buffer, v: u8)  -> bool { return buffer_write(buf, v) }
buffer_write_u16 :: proc(buf: ^Buffer, v: u16) -> bool { return buffer_write(buf, v) }
buffer_write_u32 :: proc(buf: ^Buffer, v: u32) -> bool { return buffer_write(buf, v) }
buffer_write_u64 :: proc(buf: ^Buffer, v: u64) -> bool { return buffer_write(buf, v) }
buffer_write_i8  :: proc(buf: ^Buffer, v: i8)  -> bool { return buffer_write(buf, v) }
buffer_write_i16 :: proc(buf: ^Buffer, v: i16) -> bool { return buffer_write(buf, v) }
buffer_write_i32 :: proc(buf: ^Buffer, v: i32) -> bool { return buffer_write(buf, v) }
buffer_write_i64 :: proc(buf: ^Buffer, v: i64) -> bool { return buffer_write(buf, v) }

// ── Read integers ─────────────────────────────────────────────────────────────

buffer_read_u8  :: proc(buf: ^Buffer) -> (u8,  bool) { return buffer_read(buf, u8)  }
buffer_read_u16 :: proc(buf: ^Buffer) -> (u16, bool) { return buffer_read(buf, u16) }
buffer_read_u32 :: proc(buf: ^Buffer) -> (u32, bool) { return buffer_read(buf, u32) }
buffer_read_u64 :: proc(buf: ^Buffer) -> (u64, bool) { return buffer_read(buf, u64) }
buffer_read_i8  :: proc(buf: ^Buffer) -> (i8,  bool) { return buffer_read(buf, i8)  }
buffer_read_i16 :: proc(buf: ^Buffer) -> (i16, bool) { return buffer_read(buf, i16) }
buffer_read_i32 :: proc(buf: ^Buffer) -> (i32, bool) { return buffer_read(buf, i32) }
buffer_read_i64 :: proc(buf: ^Buffer) -> (i64, bool) { return buffer_read(buf, i64) }

// ── Write floats ──────────────────────────────────────────────────────────────

buffer_write_f16 :: proc(buf: ^Buffer, v: f16) -> bool { return buffer_write(buf, v) }
buffer_write_f32 :: proc(buf: ^Buffer, v: f32) -> bool { return buffer_write(buf, v) }
buffer_write_f64 :: proc(buf: ^Buffer, v: f64) -> bool { return buffer_write(buf, v) }

// ── Read floats ───────────────────────────────────────────────────────────────

buffer_read_f16 :: proc(buf: ^Buffer) -> (f16, bool) { return buffer_read(buf, f16) }
buffer_read_f32 :: proc(buf: ^Buffer) -> (f32, bool) { return buffer_read(buf, f32) }
buffer_read_f64 :: proc(buf: ^Buffer) -> (f64, bool) { return buffer_read(buf, f64) }
