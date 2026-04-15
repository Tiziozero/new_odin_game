package main

import (
	"encoding/binary"
	"fmt"
	"log"
	"math"
	"net"
	"sync"
	"time"
)

type Server struct {
};

type User struct {
    id int32
    // curent state
    x, y, w, h float32
    r, g, b, a float32 // color
    addr net.UDPAddr
}

type server_error struct {
    s string
}
func (s *server_error)Error() string {
    return s.s
}

func (u *User)update(data []byte) error {
    if len(data) < 8 * 4 { // all 8 fields
            log.Fatalf("Need at 4*8 (32) bytes, got %d.", len(data));
            return &server_error{"Got less than 4*8 (32) bytes"};
    }
    u.x = ReadF32(data)
    data = data[4:]
    u.y = ReadF32(data)
    data = data[4:]
    u.w = ReadF32(data)
    data = data[4:]
    u.h = ReadF32(data)
    data = data[4:]
    u.r = ReadF32(data)
    data = data[4:]
    u.g = ReadF32(data)
    data = data[4:]
    u.b = ReadF32(data)
    data = data[4:]
    u.a = ReadF32(data)
    data = data[4:]
    return nil
}
// x y w h r g b a
func (u *User)dump(data *[]byte) {
    delta := make([]byte, 9*4);
    wbuf := delta[:]
    WriteI32(wbuf, u.id);
    wbuf = wbuf[4:]
    WriteF32(wbuf, u.x);
    wbuf = wbuf[4:]
    WriteF32(wbuf, u.y);
    wbuf = wbuf[4:]
    WriteF32(wbuf, u.w);
    wbuf = wbuf[4:]
    WriteF32(wbuf, u.h);
    wbuf = wbuf[4:]
    WriteF32(wbuf, u.r);
    wbuf = wbuf[4:]
    WriteF32(wbuf, u.g);
    wbuf = wbuf[4:]
    WriteF32(wbuf, u.b);
    wbuf = wbuf[4:]
    WriteF32(wbuf, u.a);
    wbuf = wbuf[4:]
    *data = append(*data, delta...);
}


func ReadU8(b []byte) uint8 {
    return b[0]

}


func WriteU8(b []byte, v uint8) {
    b[0] = v

}


func ReadU8At(b []byte, off int) (uint8, int) {
    return b[off], off + 1

}


func WriteU8At(b []byte, off int, v uint8) int {
    b[off] = v
    return off + 1
}
// ---- i32 ----

func ReadI32(b []byte) int32 {
    return int32(binary.LittleEndian.Uint32(b))
}


func WriteI32(b []byte, v int32) {
    binary.LittleEndian.PutUint32(b, uint32(v))
}

// ---- f32 ----

func ReadF32(b []byte) float32 {
    bits := binary.LittleEndian.Uint32(b)
    return math.Float32frombits(bits)
}

func WriteF32(b []byte, v float32) {
    binary.LittleEndian.PutUint32(b, math.Float32bits(v))
}


// ---- offset variants (advance a cursor) ----

func ReadI32At(b []byte, off int) (int32, int) {
    return ReadI32(b[off:]), off + 4
}

func WriteI32At(b []byte, off int, v int32) int {
    WriteI32(b[off:], v)
    return off + 4
}

func ReadF32At(b []byte, off int) (float32, int) {
    return ReadF32(b[off:]), off + 4
}

func WriteF32At(b []byte, off int, v float32) int {

    WriteF32(b[off:], v)

    return off + 4
}

func main() {
    log.Println("Hello from Golang!");
    addr, err := net.ResolveUDPAddr("udp", "127.0.0.1:3031");
    if err != nil {
        panic("Failed to resolve udp addr.");
    }
    listener, err := net.ListenUDP("udp4", addr)
    if err != nil {
        panic("err in dial udp.");
    }
    defer listener.Close();

    user_mutex := sync.Mutex{}
    users := make(map[int]User);
    // sender thread
    go func(listener *net.UDPConn, m *sync.Mutex, users map[int]User) {
        // every 50 milliseconds
        ticker := time.NewTicker(1000 * time.Millisecond)
        defer ticker.Stop()
        for range ticker.C {
            // array of array of bytes to send to uysers
            packed := make([][]byte, 0);
            for id, user := range users {
                user.id = int32(id) //double check
                data := make([]byte, 0);
                data = append(data, 3); // append 3 - update
                user.dump(&data)
                for _, b := range data {
                    fmt.Printf("%.2x ", b);
                }
                fmt.Println("");
                packed = append(packed, data)
            }
            i := 0
            // send
            for _, user := range users {
                for _, data := range packed {
                    n, err := listener.WriteTo(data, &user.addr)
                    if err != nil {
                        log.Fatalf("Error in sending udp %s", err.Error())
                    }
                    if n == 0 {
                        log.Fatalf("Sent 0 bytes.")
                    }
                    log.Printf("Wrote %d bytes.", n);
                }
                log.Printf("%d Wrote data to user %d (%d packets)",
                i, user.id, len(packed))
                i += 1;
            }
        }
    }(listener, &user_mutex, users)

    for {
        b   := make([]byte, 1024);
        oob := make([]byte, 1024);
        n, oobn, _, sender, err := listener.ReadMsgUDP(b, oob);
        if err != nil {
            log.Fatal(err)
        }
        log.Printf("Read %d bytes into b, %d into oob\n", n, oobn)
        b = b[:n]
        msg_kind := ReadU8(b);
        b = b[1:]
        if msg_kind == 1 { // connect request
            id := ReadI32(b);
            log.Printf("Connect request from %d", id);
            _, ok := users[int(id)];
            if ok {
                log.Fatalf("User %d already exists.", id);
            }
            users[int(id)] = User{id: id, addr: *sender};
            sent_count, _, err :=
                    listener.WriteMsgUDP([]byte("ok_connect"),
                                            nil, sender)
            if err != nil {
                log.Fatal(err)
            }
            log.Println("Wrote bytes", sent_count)
        } else if msg_kind == 2 { // data
            log.Printf("got data \"%s\".\n", string(b[1:]))
        } else if msg_kind == 3 { // update
            id := ReadI32(b)
            b = b[4:]
            if id < 0 {
                log.Fatal("Id less than 0, likely malforemd data.");
            }
            user, ok := users[int(id)];
            if !ok {
                log.Fatalf("Id %d update but user doesn't exits.", id);
            }
            user.update(b)
            users[int(id)] = user;
        } else {
            log.Printf("Unhandled message kind %d\n", msg_kind)
        }
    }
}
