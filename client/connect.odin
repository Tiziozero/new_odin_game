package main

import "core:fmt"
import "core:math/rand"
import "core:net"
import "core:time"
import "project:common/buffer_io"
import "project:common/game"
import "project:common/networking"
init_game_con :: proc(s: ^State) -> i32 {
    ID = u32(rand.int31())
    socket, err := net.make_unbound_udp_socket(.IP4)
    if err != .None {
        panic("Err is not none in creating socket")
    }
    // request_buf : [dynamic]byte;
    // append(&request_buf, networking.MSG_CONNECT);
    rbuf := buffer_io.buffer_make(1024)
    b := networking.init_send_message(.CONNECT, ID)
    buffer_io.buffer_write_u32(&b, ID)
    // resolve server endpoint
    server_endpoint, _ := net.resolve_ip4(networking.SERVER_ENDPOINT)
    serr := networking.send_message(socket, server_endpoint, &b)
    if serr != .None {
        panic("err in sending connection request")
    }
    fmt.printfln("Wrote connection")
    // set endpoint
    s.socket = socket
    s.server_endpoint = server_endpoint

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

    if string(recv_buf[:rn]) != "ack" {
        panic("not ack")
    }
    b = networking.init_send_message(.GET_STATE, ID)
    serr = networking.send_message(socket, server_endpoint, &b)
    if serr != .None {
        panic("err in sending connection request")
    }
    fmt.printfln("Wrote request state")
    {
        recv_buf_b := buffer_io.buffer_make(1024)
        rn, endp, rerr := net.recv_udp(socket, recv_buf_b.data[:])
        if rerr != .None {
            panic("Err in receiving from server")
        }
        if endp != server_endpoint {
            panic("Received packet from someone not server")
        }
        recv_buf_b.len = rn
        count, ok := buffer_io.buffer_read_u32(&recv_buf_b)
        fmt.printfln("got %d entities count", count)
        for k in 0 ..< count {
            id, ok := buffer_io.buffer_read_u32(&recv_buf_b)
            if !ok {
                panic("Failed to read id")
            }
            delta := game.EntityDelta{}
            game.unpack_entity(&recv_buf_b, &delta)
            e := s.state_entities[id];
            game.implement_entity_delta(&e, &delta);
            s.state_entities[id] = e
            e.id = id
        }
        buffer_io.buffer_destroy(&recv_buf_b)
    }
    buffer_io.buffer_destroy(&rbuf)

    s.connected = true
    return 0
}
