package main

import "core:fmt"
import "core:math/rand"
import "core:net"
import "core:time"
import "project:common/buffer_io"
import "project:common/game"
init_game_con :: proc(s: ^State) -> i32 {
    ID = u32(rand.int31())
    fmt.println("id:", ID)

    socket, err := net.make_unbound_udp_socket(.IP4)
    if err != .None {
        panic("Err is not none in creating socket")
    }

    // Store socket/endpoint immediately so handle_server_msg can use them.
    server_endpoint, _ := net.resolve_ip4(game.SERVER_ENDPOINT)

    s.socket = socket
    s.server_endpoint = server_endpoint

    // FIXED: these maps get written into below (via unpack_game_data),
    // but nothing else in the file initializes them before this point.
    // Writing into a nil map panics, so make sure they exist first.
    if s.state_entities == nil {
        s.state_entities = make(map[game.EntityHandle]game.Entity)
    }
    if s.current_entities == nil {
        s.current_entities = make(map[game.EntityHandle]game.Entity)
    }

    // ------------------------------------------------------------
    // Send CONNECT
    // ------------------------------------------------------------

    buf := game.init_send_message()

    game.pack_client_message(&buf, {kind=.CONNECT, data=game.ConnectMsg{user_id=ID}})

    nerr := game.send_message(socket, server_endpoint, &buf)
    if nerr != .None {
        panic("err in sending connection request")
    }

    fmt.printfln("Wrote connection request")

    // ------------------------------------------------------------
    // Receive + parse the initial GAME_DATA
    // ------------------------------------------------------------
    // FIXED: the server's CONNECT handler sends exactly ONE packet back —
    // the GAME_DATA reply itself (see handle_user_msg's .CONNECT branch:
    // it writes u8(GAME_DATA) + pack_game(g, buf, true) and sends that,
    // nothing else). The old code read that packet into a throwaway
    // [1024]byte array and discarded it, then waited on a SECOND recv_udp
    // for "initial GAME_DATA" that the server never sends — that call
    // would just hang (or time out) forever.
    //
    // Also note: this reply is written directly via pack_game(..., true),
    // NOT via pack_server_message's .GAME_DATA case, so it has no
    // energy/abilities/move_to header — just entity + projectile data.
    // That means it can't go through handle_server_msg (which expects
    // that header); read the kind byte here and hand the rest straight
    // to unpack_game_data.

    net.set_option(socket, .Receive_Timeout, 3 * time.Second)

    recv_buf := buffer_io.buffer_make(1024)
    defer buffer_io.buffer_destroy(&recv_buf)

    rn, endpoint, rerr := net.recv_udp(socket, recv_buf.data[:])
    if rerr != .None {
        panic("Err in receiving connection response")
    }

    if endpoint != server_endpoint {
        panic("Received packet from someone not server")
    }

    recv_buf.len = rn
    fmt.printfln("Received connection response (%d bytes)", rn)

    kind_raw, kok := buffer_io.buffer_read_u8(&recv_buf)
    if !kok {
        panic("Failed to read message kind from initial game state")
    }

    if game.MsgKind(kind_raw) != .GAME_DATA {
        fmt.println("Unexpected kind:", game.MsgKind(kind_raw))
        panic("Expected GAME_DATA as the CONNECT response")
    }

    // populates s.state_entities (and projectiles) directly, so the
    // ID lookup right after init_game_con in main() succeeds.
    data := game.unpack_game_data(&recv_buf)
    apply_game_data(s, data)

    fmt.println("Parsed initial game state.")

    // ------------------------------------------------------------
    // Tell server that we are ready to start receiving game updates
    // ------------------------------------------------------------

    start_buf := game.init_send_message()

    game.pack_client_message(&start_buf, {kind=.START_GAME, data=game.StartGameMsg{user_id=ID}})
    fmt.println("start buf:", start_buf.data[:start_buf.len])

    merr := game.send_message(socket, server_endpoint, &start_buf)
    if merr != .None {
        panic("err in sending START_GAME")
    }

    fmt.printfln("Sent START_GAME")

    s.connected = true

    return 0
}
