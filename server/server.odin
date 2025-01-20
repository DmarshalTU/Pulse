// server.odin
package pulse_protocol_server

import "core:fmt"
import "core:net"
import "core:os"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:time"
import "core:uuid"

import "../core/protocol"
import "../core/serialization"
import "../core/tracing"
import "../registry"

// Server Configuration
Server_Config :: struct {
    host: string,
    port: int,
    max_connections: int,
}

// Server State
Server :: struct {
    config: Server_Config,
    listener: net.TCP_Socket,
    registry: ^protocol.Service_Registry,
    running: bool,
    connections: [dynamic]net.TCP_Socket,
    mutex: sync.Mutex,
}

// Create a new server instance
create_server :: proc(config: Server_Config) -> (^Server, protocol.Pulse_Error) {
    // Create server instance
    server := new(Server)
    server.config = config
    server.registry = protocol.create_service_registry()
    server.running = false
    server.connections = make([dynamic]net.TCP_Socket)

    // Create server endpoint
    endpoint := net.Endpoint{
        address = net.parse_address(config.host),
        port = config.port,
    }

    // Create TCP listener
    listener, listen_err := net.listen_tcp(endpoint)
    if listen_err != nil {
        fmt.eprintln("Failed to create server:", listen_err)
        return nil, .NETWORK_ERROR
    }

    server.listener = listener
    return server, .NONE
}

// Handle individual client connection
handle_connection :: proc(server: ^Server, conn: net.TCP_Socket) {
    // Generate a unique trace ID for this connection
    trace_id := uuid.uuid_to_string(uuid.new())
    defer delete(trace_id)

    // Log connection attempt
    tracing.write_trace_event(
        .INFO,
        "pulse_server",
        "New connection accepted",
        trace_id
    )

    defer net.close(conn)

    // Receive buffer
    buffer: [2048]u8
    bytes_read, recv_err := net.recv_tcp(conn, buffer[:])
    if recv_err != nil {
        // Log receive error with trace context
        tracing.write_trace_event(
            .ERROR,
            "pulse_server",
            fmt.tprintf("Connection read error: %v", recv_err),
            trace_id
        )
        return
    }

    // Deserialize message
    message, ok := serialization.deserialize_pulse_message(buffer[:bytes_read])
    if !ok {
        // Log deserialization error
        tracing.write_trace_event(
            .ERROR,
            "pulse_server",
            "Failed to deserialize message",
            trace_id
        )
        return
    }

    // Process message based on type
    #partial switch message.message_type {
    case .HANDSHAKE:
        handle_handshake(server, &message, conn, trace_id)

    case .SERVICE_REGISTER:
        handle_service_registration(server, &message, conn, trace_id)

    case .SERVICE_DISCOVER:
        handle_service_discovery(server, &message, conn, trace_id)

    case .REQUEST:
        handle_service_request(server, &message, conn, trace_id)

    case:
        // Log unhandled message type
        tracing.write_trace_event(
            .WARN,
            "pulse_server",
            fmt.tprintf("Unhandled message type: %v", message.message_type),
            trace_id
        )
    }
}

// Handle handshake
handle_handshake :: proc(
    server: ^Server,
    message: ^protocol.Pulse_Message,
    conn: net.TCP_Socket,
    trace_id: string
) {
    // Log handshake attempt
    tracing.write_trace_event(
        .INFO,
        "pulse_server",
        fmt.tprintf("Received handshake from: %s", message.source_service.name),
        trace_id
    )

    // Prepare response
    response_message := protocol.create_pulse_message(
        .RESPONSE,
        protocol.create_service_metadata("pulse_server", "0.1.0", "localhost", server.config.port),
        message.source_service,
        []u8("Handshake Accepted")
    )

    // Serialize and send response
    response_data := serialization.serialize_pulse_message(&response_message)
    _, send_err := net.send_tcp(conn, response_data)
    if send_err != nil {
        // Log send error
        tracing.write_trace_event(
            .ERROR,
            "pulse_server",
            fmt.tprintf("Handshake send error: %v", send_err),
            trace_id
        )
    }
}

// Handle service registration
handle_service_registration :: proc(server: ^Server, message: ^protocol.Pulse_Message, conn: net.TCP_Socket) {
    // Register the service
    service_id := protocol.register_service(server.registry, message.source_service)

    // Prepare response
    response_message := protocol.create_pulse_message(
        .RESPONSE,
        protocol.create_service_metadata("pulse_server", "0.1.0", "localhost", server.config.port),
        message.source_service,
        []u8(fmt.tprintf("Service registered with ID: %v", service_id))
    )

    // Serialize and send response
    response_data := serialization.serialize_pulse_message(&response_message)
    net.send_tcp(conn, response_data)
}

// Handle service discovery
handle_service_discovery :: proc(server: ^Server, message: ^protocol.Pulse_Message, conn: net.TCP_Socket) {
    // Find services by name from request payload
    service_name := string(message.payload)
    discovered_services := protocol.find_services_by_name(server.registry, service_name)

    // Serialize discovered services
    discovered_services_data := make([]u8, 0, 1024)
    for service in discovered_services {
        service_info := fmt.tprintf("%s:%s@%s:%d;",
            service.name, service.version, service.host, service.port)
        discovered_services_data = append(discovered_services_data, []u8(service_info)...)
    }

    // Prepare response
    response_message := protocol.create_pulse_message(
        .RESPONSE,
        protocol.create_service_metadata("pulse_server", "0.1.0", "localhost", server.config.port),
        message.source_service,
        discovered_services_data
    )

    // Serialize and send response
    response_data := serialization.serialize_pulse_message(&response_message)
    net.send_tcp(conn, response_data)
}

// Handle service request
handle_service_request :: proc(server: ^Server, message: ^protocol.Pulse_Message, conn: net.TCP_Socket) {
    fmt.println("Received request from:", message.source_service.name)

    // Prepare generic response
    response_message := protocol.create_pulse_message(
        .RESPONSE,
        protocol.create_service_metadata("pulse_server", "0.1.0", "localhost", server.config.port),
        message.source_service,
        []u8("Request processed")
    )

    // Serialize and send response
    response_data := serialization.serialize_pulse_message(&response_message)
    net.send_tcp(conn, response_data)
}

// Start the server
start_server :: proc(server: ^Server) -> protocol.Pulse_Error {
    // Initialize trace registry
    tracing.init_trace_registry()

    // Add console trace writer
    tracing.add_trace_writer(protocol.Trace_Writer{
        write = cast(proc(^protocol.Trace_Event))tracing.console_trace_writer,
    })

    // Add file trace writer
    file_writer := tracing.create_file_trace_writer("pulse_server_traces.log")
    tracing.add_trace_writer(protocol.Trace_Writer{
        write = cast(proc(^protocol.Trace_Event))tracing.file_trace_writer_proc,
    })

    // Log server start
    tracing.write_trace_event(
        .INFO,
        "pulse_server",
        fmt.tprintf("Starting Pulse Protocol Server on %s:%d",
            server.config.host, server.config.port)
    )

    if server.running {
        tracing.write_trace_event(
            .WARN,
            "pulse_server",
            "Server already running"
        )
        return .NETWORK_ERROR
    }

    server.running = true

    // Main accept loop
    for server.running {
        client_conn, source, accept_err := net.accept_tcp(server.listener)
        if accept_err != nil {
            tracing.write_trace_event(
                .ERROR,
                "pulse_server",
                fmt.tprintf("Connection accept error: %v", accept_err)
            )
            continue
        }

        // Log connection source
        tracing.write_trace_event(
            .INFO,
            "pulse_server",
            fmt.tprintf("Accepted connection from %v", source)
        )

        // Handle connection in a separate thread/goroutine
        go handle_connection(server, client_conn)
    }

    return .NONE
}

// Stop the server
stop_server :: proc(server: ^Server) {
    server.running = false
    net.close(server.listener)

    // Close all active connections
    for conn in server.connections {
        net.close(conn)
    }
}

// Main server initialization and run
main :: proc() {
    // Server configuration
    config := Server_Config{
        host = "127.0.0.1",
        port = 8080,
        max_connections = 100,
    }

    // Create and start server
    server, err := create_server(config)
    if err != .NONE {
        tracing.write_trace_event(
            .CRITICAL,
            "pulse_server",
            fmt.tprintf("Failed to create server: %v", err)
        )
        os.exit(1)
    }

    // Start server (blocks)
    start_server(server)
}
