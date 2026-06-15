package networking

import "core:fmt"
import "core:net";
import "project:common/buffer_io"
MsgKind :: enum u8 {
    CONNECT,
    DATA,
    UPDATE,
    GET_STATE,
    PING,
    PING_RESPOND,
    GAME_DATA,
    USER_DATA,
    USER_MSG,
}
UserMsgMoveKind :: enum u8 {
    MOVE,
    ABILITY,
}
// ADDR :: "172.31.138.162";
// SERVER_ENDPOINT :: "172.31.138.162:8081";
ADDR :: "127.0.0.1";
SERVER_ENDPOINT :: "127.0.0.1:8081";
init_udp_socket :: proc(port := 0) -> (net.UDP_Socket, net.Network_Error) {
    sock_addr := net.parse_address(ADDR, false);
    socket, err := net.make_bound_udp_socket(sock_addr, port);
    if err != net.Create_Socket_Error.None {
        fmt.println("Error in creating udp socket.", err);
        return {}, err;
    }
    return socket, net.Create_Socket_Error.None;
}
init_send_user_msg :: proc(kind: UserMsgMoveKind,
    user_id: u32) -> buffer_io.Buffer {

    b := buffer_io.buffer_make(1024)

    // user message
    buffer_io.buffer_write_u8(&b, u8(MsgKind.USER_MSG))
    buffer_io.buffer_write_u32(&b, user_id)
    buffer_io.buffer_write_u8(&b, u8(kind))
    return b
}
init_send_message :: proc(kind: MsgKind,
    user_id: u32) -> buffer_io.Buffer {

    b := buffer_io.buffer_make(1024)

    buffer_io.buffer_write_u8(&b, u8(kind))
    buffer_io.buffer_write_u32(&b, user_id)
    return b
}
send_message :: proc(socket: net.UDP_Socket, endpoint: net.Endpoint,
    b: ^buffer_io.Buffer) -> net.UDP_Send_Error {
    n, err := net.send(socket, b.data[:buffer_io.buffer_written(b)], endpoint)
    assert(n == buffer_io.buffer_written(b));
    buffer_io.buffer_destroy(b)
    return err;
}
