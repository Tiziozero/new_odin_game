package main

import (
	"log"
	"math"
	"net"
)

type Server struct {
};

type User struct {
}


func readI16(msg []byte) (int16, bool) {
    if len(msg) < 2 {
        return 0, false
    }

    v := int16(msg[0]) |
         int16(msg[1])<<8 |
         int16(msg[2])<<16 |
         int16(msg[3])<<24
    msg = msg[2:]
    return v, true
}
func readI32(msg []byte) (int32, bool) {
    if len(msg) < 4 {
        return 0, false
    }
    v := int32(msg[0]) |
         int32(msg[1])<<8 |
         int32(msg[2])<<32 |
         int32(msg[3])<<24
    msg = msg[4:]
    return v, true
}
func readU8(msg []byte) (uint8, bool) {
    v := uint8(msg[0])
    return v, true;
}
func readU32(msg []byte) (uint32, bool) {
    if len(msg) < 4 {
        return 0, false
    }
    v := uint32(msg[0]) |
         uint32(msg[1])<<8 |
         uint32(msg[2])<<32 |
         uint32(msg[3])<<24
    msg = msg[4:]
    return v, true
}
func readF32(msg []byte) (float32, bool) {
    v, ok := readU32(msg);
    if !ok {
        log.Fatal("Failed to parse u32 for read f32");
        return 0, false
    }
    return math.Float32frombits(v), true
}
func writeU32LE(buf *[]byte, v uint32) {
    *buf = append(*buf,
        byte(v),
        byte(v>>8),
        byte(v>>16),
        byte(v>>24),
    )
}
func writeI32LE(buf *[]byte, v int32) {
    writeU32LE(buf, uint32(v))
}
func writeF32LE(buf *[]byte, v float32) {
    bits := math.Float32bits(v)

    *buf = append(*buf,
        byte(bits),
        byte(bits>>8),
        byte(bits>>16),
        byte(bits>>24),
    )
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

    users := make(map[int]User);

    for {
        b   := make([]byte, 1024);
        oob := make([]byte, 1024);
        n, oobn, _, sender, err := listener.ReadMsgUDP(b, oob);
        if err != nil {
            log.Fatal(err)
        }
        log.Printf("Read %d bytes into b, %d into oob\n", n, oobn)
        b = b[:n]
        msg_kind, ok := readU8(b);
        if !ok {
            log.Fatal("Failed to read message kind");
        }
        if msg_kind == 1 { // connect request
            id, ok := readU32(b);
            if !ok {
                log.Fatal("Failed to read user id from message");
            }
            users[int(id)] = User{};
            sent_count, _, err :=
                    listener.WriteMsgUDP([]byte("ok_connect"),
                                            nil, sender)
            if err != nil {
                log.Fatal(err)
            }
            log.Println("Wrote bytes", sent_count)
        } else if msg_kind == 2 { // data
            log.Printf("got data \"%s\".\n", string(b[1:]))
            sent_count, _, err :=
                    listener.WriteMsgUDP([]byte("ok_msg"),
                                            nil, sender)
            if err != nil {
                log.Fatal(err)
            }
            log.Println("Wrote bytes", sent_count)
        } else {
            log.Printf("Unhandled message kind %d\n", msg_kind)
        }
    }
}
