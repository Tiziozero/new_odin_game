import socket


with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
    s.bind(("127.0.0.1", 3031))
    print("Listening on port 3031");
    user_data = {}
    while True:
        try:
            data, addr = s.recvfrom(1024);
            print(f"Received \"{data.decode()}\" from {addr}.");
            if addr not in user_data.keys():
                id = data.split()[1]
                print("new user:", addr, "id:", id);
                s.sendto(b'ok', addr);
            user_data[addr] = data;
            send_data = b''
            send_data += data
            sent_count = s.sendto(send_data, addr);
        except Exception as e:
            print("Expcetion:", e)
            break;
