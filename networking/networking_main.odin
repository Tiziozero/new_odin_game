package networking

import "core:math/rand"
import "core:strings"
import "core:fmt"
import "core:net";
MSG_INDICIES :: u8;
MSG_CONNECT :: 1;
MSG_DATA :: 2;
MSG_UPDATE :: 3;
Entity :: struct {
    id: i32,
    x, y, w, h,
    r, g, b, a: f32
};

dump_user :: proc(u: Entity, data: ^[dynamic]byte) {
    append_i32(data, u.id);
    append_f32(data, u.x);
    append_f32(data, u.y);
    append_f32(data, u.w);
    append_f32(data, u.h);
    append_f32(data, u.r);
    append_f32(data, u.g);
    append_f32(data, u.b);
    append_f32(data, u.a);
}
load_user :: proc(u: ^Entity, data: ^[]byte) {
    assert(len(data) > 4*8);
    u.x = read_f32(data^)
    data^ = data^[4:]
    u.y = read_f32(data^)
    data^ = data^[4:]
    u.w = read_f32(data^)
    data^ = data^[4:]
    u.h = read_f32(data^)
    data^ = data^[4:]

    u.r = read_f32(data^)
    data^ = data^[4:]
    u.g = read_f32(data^)
    data^ = data^[4:]
    u.b = read_f32(data^)
    data^ = data^[4:]
    u.a = read_f32(data^)
    data^ = data^[4:]
}


// u8 is a single byte — read/write is a direct index.
// append_u8 follows the same ^[dynamic]byte pattern.

read_u8 :: proc(b: []byte) -> u8 {
    return b[0]
}

write_u8 :: proc(b: []byte, v: u8) {
    b[0] = v
}

append_u8 :: proc(buf: ^[dynamic]byte, v: u8) {
    append(buf, v)
}

read_u8_at :: proc(b: []byte, off: int) -> (v: u8, next: int) {
    return b[off], off + 1
}

// ---- i32 ----

read_i32 :: proc(b: []byte) -> i32 {
    return (i32)(b[0]) |
           (i32)(b[1]) << 8  |
           (i32)(b[2]) << 16 |
           (i32)(b[3]) << 24
}

write_i32 :: proc(b: []byte, v: i32) {
    b[0] = byte(v)
    b[1] = byte(v >> 8)
    b[2] = byte(v >> 16)
    b[3] = byte(v >> 24)

}


// ---- f32 ----

read_f32 :: proc(b: []byte) -> f32 {
    bits := (u32)(b[0]) |
            (u32)(b[1]) << 8  |
            (u32)(b[2]) << 16 |
            (u32)(b[3]) << 24

    return transmute(f32)bits
}

write_f32 :: proc(b: []byte, v: f32) {
    bits := transmute(u32) v
    b[0] = byte(bits)
    b[1] = byte(bits >> 8)

    b[2] = byte(bits >> 16)
    b[3] = byte(bits >> 24)
}

// ---- dynamic buffer appenders ----

append_i32 :: proc(buf: ^[dynamic]byte, v: i32) {
    append(buf,
        byte(v),
        byte(v >> 8),
        byte(v >> 16),
        byte(v >> 24),
    )
}


append_f32 :: proc(buf: ^[dynamic]byte, v: f32) {
    bits := transmute(u32)v
    append(buf,
        byte(bits),
        byte(bits >> 8),

        byte(bits >> 16),

        byte(bits >> 24),
    )
}

// ---- offset variants (returns next cursor position) ----

read_i32_at :: proc(b: []byte, off: int) -> (v: i32, next: int) {
    return read_i32(b[off:]), off + 4
}

read_f32_at :: proc(b: []byte, off: int) -> (v: f32, next: int) {
    return read_f32(b[off:]), off + 4
}
handle_server_msg_update_entity :: proc(e: ^Entity, msg: []byte) {
    fmt.printfln("msg of length %d.", len(msg));
    assert(len(msg) > 1);
}

init_udp_sock :: proc() -> (net.UDP_Socket, net.Network_Error) {

    sock_addr := net.parse_address("127.0.0.1", false);
    socket, err := net.make_bound_udp_socket(sock_addr, 0);
    if err != net.Create_Socket_Error.None {
        fmt.println("Error in creating udp socket.", err);
        return {}, err;
    }
    fmt.println("Socket", socket);
    return socket, net.Create_Socket_Error.None;
}

udp_send_buf :: proc(socket: net.UDP_Socket, buf: []byte) -> int {
    server_endpoint, _ := net.resolve_ip4("127.0.0.1:3031");
    n, e := net.send_udp(socket, buf, server_endpoint);
    if e != .None {
        panic("Faild to send from socker.");
    }
    return n
}
udp_handle_recv :: proc(socket: net.UDP_Socket) -> string {
    buf: [1024]byte;
    n, endpoint, err := net.recv_udp(socket, buf[:]);
    if err != .None {
        panic("recevied 0 bytes + error");
    }
    if n == 0 {
        if err != .None {
            panic("recevied 0 bytes + error");
        } else {
            return ""
            // fmt.println("recevied 0 from", endpoint);
        }
    } else {
        s := strings.clone_from_bytes(buf[:n]);
        fmt.printfln("Received %d bytes \"%s\".", n, s);
        return s;
    }
}
udp_send_sb :: proc(socket: net.UDP_Socket, sb: strings.Builder) {
   udp_send_buf(socket, sb.buf[:]);
}
nmain :: proc() -> int{
    id := rand.int31();
    id %= 1000
    fmt.printfln("id %d", id)
    udp_sock, udp_sock_err := init_udp_sock();
    if udp_sock_err != net.Create_Socket_Error.None {
        panic("Failed to init udp socket.");
    }
    defer net.close(udp_sock);
    // udp_send_sb(udp_sock, s);
    // use messages now
    data: [dynamic]byte;
    append_u8(&data, MSG_CONNECT);
    append_i32(&data, id);
    sent_count := udp_send_buf(udp_sock, data[:]);
    fmt.printfln("Sent %d bytes.", sent_count);
    r := udp_handle_recv(udp_sock);
    if r == "" {
        panic("Got nothing from server.");
    }

    u := Entity{};
    u.id = i32(id);

    u.x = 120;
    u.y = 121;
    u.w = 100;
    u.h = 101;
    u.r = 122;
    u.g = 123;
    u.b = 124;
    u.a = 255;
    send_data :[dynamic]byte
    append_u8(&send_data, MSG_UPDATE);
    dump_user(u, &send_data)

    for i in 0..<3 {
        /* s := strings.builder_make();
        strings.write_byte(&s, byte(MSG_DATA));
        // strings.builder_reset(&s);
        fmt.sbprintf(&s, " MSG arbitrary_message_%d.", i);
        udp_send_buf(udp_sock, s.buf[:]);
        strings.builder_destroy(&s)*/
        udp_send_buf(udp_sock, send_data[:]);
        udp_handle_recv(udp_sock);
    }
    return 1;
}
