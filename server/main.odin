package main

import "core:sync"
import "core:strings"
import "core:mem"
import "core:net"
import "core:fmt"
import "project:common/game"
import "project:common/networking"
import "project:common/buffer_io"

@private
Game :: struct {
    entities: map[game.EntityHandle]game.Entity,
    entities_lock: sync.Mutex,
    socket: net.UDP_Socket,
}

game_init :: proc() -> Game {
    g := Game{}
    g.entities = make(map[int]game.Entity);
    return g;
}

init_server_socket :: proc(g: ^Game) {
    s, _ := networking.init_udp_socket(port=8081);
    g.socket = s;
}
game_handle_msg :: proc(g: ^Game, buf: ^buffer_io.Buffer) {
}
import "core:time"
import "core:thread"
handle_receiver_loop :: proc(g: ^Game, n: int) {
    duration := time.Duration(n) * time.Millisecond
    buf := buffer_io.buffer_make(1024);
    for {
        fmt.println("loop");
        n, endpoint, err := net.recv_udp(g.socket, buf.data[:]);
        if err != .None {
            panic("recevied error");
        }
        buf.len = n
        for i in 0..< len(buf.data[:n]) {
            fmt.printfln(" %.2x", buf.data[i])
        }
        fmt.printfln("msg len %d", buf.len);
        msg, ok := buffer_io.buffer_read_u8(buf);
        if !ok {
            panic("failed to read u8 from user msg buffer");
        }
        if msg == networking.MSG_CONNECT {
            fmt.println("Connect");
            id, ok := buffer_io.buffer_read_u32(buf);
            if !ok {
                panic("Failed to read u32, user id for connect");
            }
            fmt.printfln("access token: %d", id);
            sync.mutex_lock(&g.entities_lock);
            g.entities[int(id)] = game.Entity{};
            for k,e in g.entities {
                fmt.println(k, e)
            }
            sync.mutex_unlock(&g.entities_lock);
            // send ok
            buffer_io.buffer_reset(&buf);
            b := strings.builder_make()
            fmt.sbprint(&b, "ack");
            nn, e := net.send_udp(g.socket, b.buf[:], endpoint);
            strings.builder_destroy(&b)
        } else {
            panic("unknown message");
        }
        buffer_io.buffer_reset(&buf);
    }
}
pack_game_loop_data :: proc(g: ^Game, buf: ^buffer_io.Buffer) -> int {
    buf.data[0] = 65;
    buf.data[1] = 0;
    buf.len = 2;
    return 2;
}
handle_sender_loop :: proc(g: ^Game, n: int) {
    duration := time.Duration(n) * time.Millisecond
    buf := buffer_io.buffer_make(1024);
    for {
        fmt.println("send loop");
        start := time.now()
        elapsed := time.since(start)
        n := pack_game_loop_data(g, &buf);

        if elapsed < duration {
            time.sleep(duration - elapsed)
        }
        buffer_io.buffer_reset(&buf);
    }
}

thread_receiver_fn :: proc(data: rawptr) {
    handle_receiver_loop(transmute(^Game)data, 100);
}
thread_sender_fn :: proc(data: rawptr) {
    // handle_sender_loop(transmute(^Game)data, 100);
}

main :: proc() {
    g := game_init()
    init_server_socket(&g)
    t_receiver := thread.create_and_start_with_data(data=&g, fn=thread_receiver_fn);
    t_sender := thread.create_and_start_with_data(data=&g, fn=thread_sender_fn);


    thread.join(t_receiver)
    thread.join(t_sender)
    fmt.println("Hellope!");
}
