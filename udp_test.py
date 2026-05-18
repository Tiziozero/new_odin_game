import socket

# in little endian
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    data = b'\x01' # msg connect
    data += b'\x07\x00\x00\x00'
    sock.sendto(data, ('127.0.0.1', 8081))
    data, endpoint = sock.recvfrom(1024);
    print(data.decode(), endpoint)
    pass
