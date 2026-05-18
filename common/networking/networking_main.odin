package networking

import "core:strings"
import "core:fmt"
import "core:net";
import "project:common/buffer_io"
MSG_INDICIES :: u8;
MSG_CONNECT :: 1;
MSG_DATA :: 2;
MSG_UPDATE :: 3;

init_udp_socket :: proc(port := 0) -> (net.UDP_Socket, net.Network_Error) {
    sock_addr := net.parse_address("127.0.0.1", false);
    socket, err := net.make_bound_udp_socket(sock_addr, port);
    if err != net.Create_Socket_Error.None {
        fmt.println("Error in creating udp socket.", err);
        return {}, err;
    }
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
