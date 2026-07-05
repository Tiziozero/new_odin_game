package main

import "core:fmt"
import "core:math/rand"
import "core:net"
import "core:time"
import "project:common/buffer_io"
import "project:common/networking"
init_game_con :: proc(s: ^State) -> i32 {
    ID = u32(rand.int31())
    socket, err := net.make_unbound_udp_socket(.IP4)
    if err != .None {
        panic("Err is not none in creating socket")
    }

    b := networking.init_send_message(.CONNECT, ID)
    buffer_io.buffer_write_u32(&b, ID)

    // resolve server endpoint and connect
    server_endpoint, _ := net.resolve_ip4(networking.SERVER_ENDPOINT)
    serr := networking.send_message(socket, server_endpoint, &b)
    if serr != .None {
        panic("err in sending connection request")
    }
    fmt.printfln("Wrote connection")


    // set timeout for receive
    net.set_option(socket, .Receive_Timeout, 3 * time.Second)
    recv_buf: [1024]byte
    rn, endp, rerr := net.recv_udp(socket, recv_buf[:])
    if rerr != .None {
        panic("Err in receiving from server")
    }
    if endp != server_endpoint {
        panic("Received packet from someone not server")
    }



    // get state first
    recv_buf_b := buffer_io.buffer_make(1024)
    rn, endp, rerr = net.recv_udp(socket, recv_buf_b.data[:])
    if rerr != .None {
        panic("Err in receiving from server")
    }
    if endp != server_endpoint {
        panic("Received packet from someone not server")
    }
    recv_buf_b.len = rn
    // handle
    handle_server_msg(s, &recv_buf_b);
    buffer_io.buffer_destroy(&recv_buf_b)

    // set endpoint
    s.socket = socket
    s.server_endpoint = server_endpoint

    s.connected = true
    return 0
}
