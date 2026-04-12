package networking

import "core:math/rand"
import "core:strings"
import "core:fmt"
import "core:net";
State :: struct {
    id: u64,
    a, b, c, d: int,
    e, f, g, h: f32,
};


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

udp_send_buf :: proc(socket: net.UDP_Socket, buf: []byte) {
    server_endpoint, _ := net.resolve_ip4("127.0.0.1:3031");
    n, e := net.send_udp(socket, buf, server_endpoint);
    if e != .None {
        panic("Faild to send from socker.");
    }
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
nmain :: proc() {
    id := rand.int31();
    udp_sock, udp_sock_err := init_udp_sock();
    if udp_sock_err != net.Create_Socket_Error.None {
        panic("Failed to init udp socket.");
    }
    defer net.close(udp_sock);
    s := strings.builder_make();
    fmt.printfln("attempting to connect. id: %d...", id);
    fmt.sbprintf(&s, "CONNECT %d", id);
    udp_send_sb(udp_sock, s);

    r := udp_handle_recv(udp_sock);
    if r == "" {
        panic("Got nothing from server.");
    }

    for i in 0..<3 {
        strings.builder_reset(&s);
        fmt.sbprintf(&s, "arbitrary message %d.", i);
        udp_send_buf(udp_sock, s.buf[:]);
        udp_handle_recv(udp_sock);
    }
    strings.builder_reset(&s);
    fmt.sbprintf(&s, "DISCONNECT %d", id);
    return;
}
