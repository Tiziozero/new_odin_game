package main

import (
	"log"
	"net"
	"strconv"
	"strings"
)

type Server struct {
};

type User struct {
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

        msg := string(b[:n]);
        bits := strings.Split(msg, " ");
        if bits[0] == "CONNECT" {
            log.Printf("Connection request\n");
            id, err := strconv.Atoi(bits[1]);
            if err != nil {
                log.Fatal(err)
            }
            log.Printf("New user %d", id)
            users[id] = User{};
            sent_count, _, err := listener.WriteMsgUDP([]byte("ok"),
                                                        nil, sender)
            if err != nil {
                log.Fatal(err)
            }
            log.Println("Wrote bytes", sent_count)
        } else { // parse ig?
        }
    }
}
