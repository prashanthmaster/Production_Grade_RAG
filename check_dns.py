import socket
host = "ep-jolly-fog-b32uc493-pooler.c-4.ap-southeast-1.aws.neon.tech"
for res in socket.getaddrinfo(host, 5432):
    print(res)
