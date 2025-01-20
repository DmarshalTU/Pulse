package pulse_protocol

import "core:fmt"
import "core:net"
import "core:os"
import "core:slice"
import "core:strings"
import "core:thread"

// Protocol constants
PULSE_PROTOCOL_VERSION :: 0_1_0
DEFAULT_PORT :: 8080

// Message types for our protocol
Message_Type :: enum u8 {
    HANDSHAKE,
    REQUEST,
    RESPONSE,
    STREAM_START,
    STREAM_DATA,
    STREAM_END,
    ERROR,
}

// Pulse protocol message structure
Pulse_Message :: struct {
    version: u16,
    message_type: Message_Type,
    payload_length: u32,
    payload: []u8,
    metadata: map[string]string,
}

// Serialization functions
serialize_message :: proc(msg: ^Pulse_Message) -> []u8 {
    // Simple serialization for now
    payload_bytes := make([]u8, len(msg.payload) + 8)  // 2 for version, 1 for type, 4 for payload length
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

    // Reconstruct version
    version := u16(data[0]) << 8 | u16(data[1])

    // Get message type
    message_type := Message_Type(data[2])

    // Reconstruct payload length
    payload_length := u32(data[3]) << 24 |
                      u32(data[4]) << 16 |
                      u32(data[5]) << 8  |
                      u32(data[6])

    // Extract payload
    payload := make([]u8, payload_length)
    copy(payload, data[8:])

    return Pulse_Message{
        version = version,
        message_type = message_type,
        payload_length = payload_length,
        payload = payload,
    }, true
}

// Server configuration
Pulse_Server :: struct {
    listener: net.TCP_Socket,
    port: int,
    max_connections: int,
    running: bool,
}

// Create a new server instance
create_server :: proc(port: int) -> (Pulse_Server, net.Network_Error) {
    server: Pulse_Server
    server.port = port
    server.max_connections = 100
    server.running = true

    endpoint := net.Endpoint{
        address = net.IP4_Loopback,
        port = port,
    }

    listener, listen_err := net.listen_tcp(endpoint)
    if listen_err != nil {
        fmt.eprintln("Failed to create server:", listen_err)
        return server, listen_err
    }

    server.listener = listener
    return server, nil
}

// Modify handle_connection to be more verbose and robust
handle_connection :: proc(conn: net.TCP_Socket) {
    // Increase buffer size to handle larger messages
    buffer: [2048]u8

    for {
        bytes_read, read_err := net.recv_tcp(conn, buffer[:])
        if read_err != nil {
            fmt.eprintln("Connection read error:", read_err)
            break
        }

        if bytes_read == 0 {
            fmt.println("Connection closed by client")
            break
        }

        fmt.printf("Received %d bytes\n", bytes_read)

        // Parse received message
        message, ok := deserialize_message(buffer[:bytes_read])
        if !ok {
            fmt.eprintln("Failed to deserialize message")
            continue
        }

        // Partial switch to handle known message types
        #partial switch message.message_type {
        case .HANDSHAKE:
            fmt.println("Received handshake:", string(message.payload))

            // Prepare and send response
            response_message := Pulse_Message{
                version = PULSE_PROTOCOL_VERSION,
                message_type = .RESPONSE,
                payload = transmute([]u8)strings.clone("Handshake Accepted"),
            }

            response_data := serialize_message(&response_message)

            _, send_err := net.send_tcp(conn, response_data)
            if send_err != nil {
                fmt.eprintln("Send error:", send_err)
                break
            }

        case .REQUEST:
            fmt.println("Received request:", string(message.payload))

            // Prepare response
            response_message := Pulse_Message{
                version = PULSE_PROTOCOL_VERSION,
                message_type = .RESPONSE,
                payload = transmute([]u8)strings.clone("Server Info: Pulse Protocol v0.1.0"),
            }

            response_data := serialize_message(&response_message)

            // Send response
            _, send_err := net.send_tcp(conn, response_data)
            if send_err != nil {
                fmt.eprintln("Send error:", send_err)
                break
            }

        case:
            fmt.println("Unhandled message type:", message.message_type)
        }
    }

    net.close(conn)
}

// Main server run loop
run_server :: proc(server: ^Pulse_Server) {
    fmt.println("Pulse Protocol Server starting on port", server.port)

    for server.running {
        client_conn, source, accept_err := net.accept_tcp(server.listener)
        if accept_err != nil {
            fmt.eprintln("Connection accept error:", accept_err)
            continue
        }

        fmt.printf("Accepted connection from %v\n", source)
        handle_connection(client_conn)
    }
}

main :: proc() {
    PORT :: DEFAULT_PORT

    // Start server in background
    server, server_err := create_server(PORT)
    if server_err != nil {
        fmt.eprintln("Failed to create server:", server_err)
        os.exit(1)
    }

    // Create and start server thread
    server_thread := thread.create(proc(t: ^thread.Thread) {
        server_ptr := (^Pulse_Server)(t.data)
        run_server(server_ptr)
    })
    server_thread.data = &server

    thread.start(server_thread)

    // Wait for server thread
    thread.join(server_thread)
}
