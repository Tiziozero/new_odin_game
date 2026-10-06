package main

import "project:common/game"


debug_log :: proc(s: ^State, pref: game.Entity) {
    append(&s.logs, "Hello, World!!")
    append(&s.logs, "Debug logs:")
    slog(s, "Last packet size: %d", s.debug_last_packet_size);
    append(&s.logs, "events!")
    slog(s,"ID: %d", ID);
    slog(s, "pos  :%.0f %.0f", s.spref.body.x, s.spref.body.y,)
    slog(s, "spos       :%.0f %.0f", pref.body.x, pref.body.y)
    slog(s, "s state pos:%.0f %.0f", s.spref.body.x, s.spref.body.y)
    slog(s, "ping? :%.5f", s.ping)
    slog(s, "move_to: %.0f:%.0f", s.move_to.x, s.move_to.y)
    slog(s, "energy: %.0f", s.energy);
    
    slog(s, "view :%d", int(s.debug) + 0)
    slog(s, "snap :%d", int(bool_snap) + 0)
}
