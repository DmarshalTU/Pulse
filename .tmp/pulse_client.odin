// pulse_client.odin
package pulse_client

import "core:fmt"
import "core:net"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

// Import the serialization logic from the server (or create a shared package)
Message_Type :: enum u8 {
    HANDSHAKE,
    REQUEST,
    RESPONSE,
    STREAM_START,
    STREAM_DATA,
    STREAM_END,
    ERROR,
}

Pulse_Message :: struct {
    version: u16,
    message_type: Message_Type,
    payload_length: u32,
    payload: []u8,
    metadata: map[string]string,
}

serialize_message :: proc(msg: ^Pulse_Message) -> []u8 {
    payload_bytes := make([]u8, len(msg.payload) + 8)
    payload_bytes[0] = u8(msg.version >> 8)
    payload_bytes[1] = u8(msg.version & 0xFF)
    payload_bytes[2] = u8(msg.message_type)

    payload_length := u32(len(msg.payload))
    payload_bytes[3] = u8(payload_length >> 24)
    payload_bytes[4] = u8(payload_length >> 16)
    payload_bytes[5] = u8(payload_length >> 8)
    payload_bytes[6] = u8(payload_length & 0xFF)

    copy(payload_bytes[8:], msg.payload)
    return payload_bytes
}

deserialize_message :: proc(data: []u8) -> (Pulse_Message, bool) {
    if len(data) < 8 {
        fmt.eprintln("Message too short for deserialization")
        return Pulse_Message{}, false
    }

    version := u16(data[0]) << 8 | u16(data[1])
    message_type := Message_Type(data[2])

    payload_length := u32(data[3]) << 24 |
                      u32(data[4]) << 16 |
                      u32(data[5]) << 8  |
                      u32(data[6])

    payload := make([]u8, payload_length)
    copy(payload, data[8:])

    return Pulse_Message{
        version = version,
        message_type = message_type,
        payload_length = payload_length,
        payload = payload,
    }, true
}

PulseClient :: struct {
    conn: net.TCP_Socket,
    server_endpoint: net.Endpoint,
}

create_client :: proc(host: string, port: int) -> (PulseClient, net.Network_Error) {
    endpoint := net.Endpoint{
        address = net.parse_address(host),
        port = port,
    }

    conn, dial_err := net.dial_tcp_from_endpoint(endpoint)
    if dial_err != nil {
        fmt.eprintln("Client connection error:", dial_err)
        return PulseClient{}, dial_err
    }

    return PulseClient{
        conn = conn,
        server_endpoint = endpoint,
    }, nil
}

send_message :: proc(client: ^PulseClient, message_type: Message_Type, payload: string) -> bool {
    message := Pulse_Message{
        version = 0_1_0,
        message_type = message_type,
        payload = transmute([]u8)strings.clone(payload),
    }

    serialized_message := serialize_message(&message)

    _, send_err := net.send_tcp(client.conn, serialized_message)
    if send_err != nil {
        fmt.eprintln("Send error:", send_err)
        return false
    }

    return true
}

receive_message :: proc(client: ^PulseClient) -> (Pulse_Message, bool) {
    buffer: [2048]u8  // Increased buffer size
    bytes_read, recv_err := net.recv_tcp(client.conn, buffer[:])
    if recv_err != nil {
        fmt.eprintln("Receive error:", recv_err)
        return Pulse_Message{}, false
    }

    // Optional: Add debug printing
    fmt.printf("Received %d bytes in response\n", bytes_read)

    // Optional: Print raw bytes for debugging
    fmt.print("Raw bytes: ")
    for i in 0..<bytes_read {
        fmt.printf("%02x ", buffer[i])
    }
    fmt.println()

    return deserialize_message(buffer[:bytes_read])
}

close_client :: proc(client: ^PulseClient) {
    net.close(client.conn)
}

main :: proc() {
    client, conn_err := create_client("127.0.0.1", 8080)
    if conn_err != nil {
        fmt.eprintln("Failed to create client:", conn_err)
        os.exit(1)
    }
    defer close_client(&client)

    // Handshake
    fmt.println("Sending handshake...")
    if !send_message(&client, .HANDSHAKE, "Hello, Pulse Server!") {
        fmt.eprintln("Handshake failed")
        os.exit(1)
    }

    // Receive handshake response
    handshake_response, handshake_ok := receive_message(&client)
    if !handshake_ok {
        fmt.eprintln("Failed to receive handshake response")
        os.exit(1)
    }
    fmt.println("Handshake response:", string(handshake_response.payload))

    // Send request
    fmt.println("Sending request...")
    if !send_message(&client, .REQUEST, "Can you provide server info?") {
        fmt.eprintln("Request failed")
        os.exit(1)
    }

    // Receive request response
    request_response, request_ok := receive_message(&client)
    if !request_ok {
        fmt.eprintln("Failed to receive request response")
        os.exit(1)
    }
    fmt.println("Request response:", string(request_response.payload))
}
