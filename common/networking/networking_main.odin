package networking

import "core:time"
import "core:math/rand"
import "core:strings"
import "core:fmt"
import "core:net";
import "core:sync";
import "core:thread";
MSG_INDICIES :: u8;
MSG_CONNECT :: 1;
MSG_DATA :: 2;
MSG_UPDATE :: 3;
State :: struct {
    udp_sock: net.UDP_Socket,
    running: i32, //atomically
    entities: map[i32]Entity,
}
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
    if len(data^) < 4*8 {
        fmt.panicf("Length is less that 4 * 8: %d.", len(data^));
    }
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

read_u8_at :: proc(b: []byte, off: i32) -> (v: u8, next: i32) {
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

read_i32_at :: proc(b: []byte, off: i32) -> (v: i32, next: i32) {
    return read_i32(b[off:]), off + 4
}

read_f32_at :: proc(b: []byte, off: i32) -> (v: f32, next: i32) {
    return read_f32(b[off:]), off + 4
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

udp_send_buf :: proc(socket: net.UDP_Socket, buf: []byte) -> i32 {
    server_endpoint, _ := net.resolve_ip4("127.0.0.1:3031");
    n, e := net.send_udp(socket, buf, server_endpoint);
    if e != .None {
        panic("Faild to send from socker.");
    }
    return i32(n)
}
udp_handle_recv_buf :: proc(socket: net.UDP_Socket, buf: []byte) -> (i32, net.UDP_Recv_Error) {
    recv, endpoint, err := net.recv_udp(socket, buf);
    if err != .None {
        panic("recevied 0 bytes + error");
    }
    // fmt.printfln("Received %d bytes.", recv);
    return i32(recv), .None
}
udp_handle_recv :: proc(socket: net.UDP_Socket) -> (data: []byte, errod: net.UDP_Recv_Error) {
    buf := make([]byte, 1024);
    n, endpoint, err := net.recv_udp(socket, buf[:]);
    if err != .None {
        panic("recevied 0 bytes + error");
    }
    if n == 0 {
        if err != .None {
            panic("recevied 0 bytes + error");
        } else {
            delete(buf); // free ofc
            return nil, .None
        }
    } else {
        return buf, .None
    }
}
udp_send_sb :: proc(socket: net.UDP_Socket, sb: strings.Builder) {
   udp_send_buf(socket, sb.buf[:]);
}
handle_unknown_user :: proc(state: ^State, id: i32) {
    state.entities[id] = Entity{id=id};
}

nmain :: proc() -> i32{
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
    fmt.printfln("Sent %d bytes (connection request).", sent_count);
    r, err := udp_handle_recv(udp_sock);
    if err != .None {
        panic("Got nothing from server.");
    }
    // connection ok?

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
    entities := make(map[i32]Entity);
    user_mutex := sync.Mutex{}
    state := State{udp_sock, 1, entities}
    receiver_thread := thread.create_and_start_with_poly_data2(
        &user_mutex, &state,
        proc(m: ^sync.Mutex, state: ^State) {
            buf: [1024]byte
            for sync.atomic_load(&state.running) == 1 {
                n, err := udp_handle_recv_buf(state.udp_sock, buf[:]);
                if err != .None {
                    fmt.eprintln("Err is not none in receiver thread", err);
                    return;
                }
                data := buf[:n]
                fmt.printfln("Got %d bytes.", n);
                msg_kind := read_u8(data);
                data = data[1:]
                switch msg_kind {
                case MSG_UPDATE: {
                    id := read_i32(data); // read id
                    data = data[4:]
                    user, ok := state.entities[i32(id)];
                    if !ok {
                        handle_unknown_user(state, id);
                        // fmt.panicf("unknown user %d", id);
                    }
                    e := &state.entities[i32(id)];
                    load_user(e, &data);
                }
                case: {
                    fmt.panicf("unknown kind %d", msg_kind);
                }
                }
            }
        }
     );
    // loop
    send_data :[dynamic]byte
    append_u8(&send_data, MSG_UPDATE);
    dump_user(u, &send_data)
    for i in 0..<30000 {
        time.sleep(time.Millisecond*100);
        fmt.println("loop:", state.entities[id]);
        udp_send_buf(udp_sock, send_data[:]);
    }
    thread.destroy(receiver_thread);
    return 1;
}
