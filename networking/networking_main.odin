package networking

import "core:math/rand"
import "core:strings"
import "core:fmt"
import "core:net";
MSG_INDICIES :: u8;
MSG_CONNECT :: 1;
MSG_DATA :: 2;
Entity :: struct {
    id: u64,
    a, b, c, d: int,
    e, f, g, h: f32,
};

read_i16 :: proc(msg: ^[]byte) -> i16 {
    if len(msg) < 2 {
        panic("msg len less thatn 2 when expected 2 for i16.");
    }
    n := (cast(^i16)&msg^[0])^
    msg^ = msg^[2:]
    return n;
}
read_i32 :: proc(msg: ^[]byte) -> i32 {
    if len(msg) < 4 {
        panic("msg len less thatn 4 when expected 4 for i32.");
    }
    n := (cast(^i32)&msg^[0])^
    msg^ = msg^[4:]
    return n;
}
read_f32 :: proc(msg: ^[]byte) -> f32 {
    if len(msg) < 4 {
        panic("msg len less thatn 4 when expected 4 for f32.");
    }
    n := (cast(^f32)&msg^[0])^
    msg^ = msg^[4:]
    return n;
}
// for writers need dynamic?
write_u8 :: proc(buf: ^[dynamic]u8, v: u8) {
    append(buf, u8(v))
}
write_i8 :: proc(buf: ^[dynamic]u8, v: i8) {
    append(buf, u8(v))
}
write_u32 :: proc(buf: ^[dynamic]u8, v: u32) {
    append(buf, u8(v))
    append(buf, u8(v >> 8))
    append(buf, u8(v >> 16))
    append(buf, u8(v >> 24))
}

write_i32 :: proc(buf: ^[dynamic]u8, v: i32) {
    write_u32(buf, cast(u32)v)
}
write_f32_le :: proc(buf: ^[dynamic]u8, v: f32) {
    bits := transmute(u32)v

    append(buf, u8(bits))
    append(buf, u8(bits >> 8))
    append(buf, u8(bits >> 16))
    append(buf, u8(bits >> 24))
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
    udp_sock, udp_sock_err := init_udp_sock();
    if udp_sock_err != net.Create_Socket_Error.None {
        panic("Failed to init udp socket.");
    }
    defer net.close(udp_sock);
    // udp_send_sb(udp_sock, s);
    // use messages now
    data: [dynamic]byte;
    write_u8(&data, MSG_CONNECT);
    write_i32(&data, id);
    sent_count := udp_send_buf(udp_sock, data[:]);
    fmt.printfln("Sent %d bytes.", sent_count);
    r := udp_handle_recv(udp_sock);
    if r == "" {
        panic("Got nothing from server.");
    }

    for i in 0..<3 {
        s := strings.builder_make();
        strings.write_byte(&s, byte(MSG_DATA));
        // strings.builder_reset(&s);
        fmt.sbprintf(&s, " MSG arbitrary_message_%d.", i);
        udp_send_buf(udp_sock, s.buf[:]);
        strings.builder_destroy(&s)
        udp_handle_recv(udp_sock);
    }
    return 1;
}
