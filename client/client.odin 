// client.odin (with tracing integration)
package pulse_client

import "core:fmt"
import "core:net"
import "core:os"
import "core:uuid"

import "../core/protocol"
import "../core/serialization"
import "../core/tracing"

// Modify connect method to include tracing
connect :: proc(client: ^Client) -> protocol.Pulse_Error {
    // Generate unique trace ID for connection attempt
    trace_id := uuid.uuid_to_string(uuid.new())
    defer delete(trace_id)

    // Log connection attempt
    tracing.write_trace_event(
        .INFO,
        "pulse_client",
        fmt.tprintf("Attempting to connect to %s:%d",
            client.config.server_host,
            client.config.server_port
        ),
        trace_id
    )

    endpoint := net.Endpoint{
        address = net.parse_address(client.config.server_host),
        port = client.config.server_port,
    }

    conn, dial_err := net.dial_tcp_from_endpoint(endpoint)
    if dial_err != nil {
        // Log connection error
        tracing.write_trace_event(
            .ERROR,
            "pulse_client",
            fmt.tprintf("Failed to connect to server: %v", dial_err),
            trace_id
        )
        return .NETWORK_ERROR
    }

    client.connection = conn
    client.is_connected = true

    // Log successful connection
    tracing.write_trace_event(
        .INFO,
        "pulse_client",
        "Successfully connected to server",
        trace_id
    )

    return .NONE
}

// Update handshake method with tracing
handshake :: proc(client: ^Client) -> (protocol.Pulse_Message, protocol.Pulse_Error) {
    if !client.is_connected {
        tracing.write_trace_event(
            .ERROR,
            "pulse_client",
            "Attempted handshake without connection"
        )
        return protocol.Pulse_Message{}, .NETWORK_ERROR
    }

    // Generate trace ID for this handshake
    trace_id := uuid.uuid_to_string(uuid.new())
    defer delete(trace_id)

    // Log handshake attempt
    tracing.write_trace_event(
        .INFO,
        "pulse_client",
        "Initiating handshake",
        trace_id
    )

    // Create handshake message
    handshake_message := protocol.create_pulse_message(
        .HANDSHAKE,
        client.config.service_metadata,
        protocol.create_service_metadata(
            "pulse_server",
            "0.1.0",
            client.config.server_host,
            client.config.server_port
        ),
        []u8("Client Handshake")
    )

    // Serialize and send message
    serialized_data := serialization.serialize_pulse_message(&handshake_message)
    _, send_err := net.send_tcp(client.connection, serialized_data)
    if send_err != nil {
        // Log send error
        tracing.write_trace_event(
            .ERROR,
            "pulse_client",
            fmt.tprintf("Handshake send error: %v", send_err),
            trace_id
        )
        return protocol.Pulse_Message{}, .NETWORK_ERROR
    }

    // Receive response
    buffer: [2048]u8
    bytes_read, recv_err := net.recv_tcp(client.connection, buffer[:])
    if recv_err != nil {
        // Log receive error
        tracing.write_trace_event(
            .ERROR,
            "pulse_client",
            fmt.tprintf("Handshake receive error: %v", recv_err),
            trace_id
        )
        return protocol.Pulse_Message{}, .NETWORK_ERROR
    }

    // Deserialize response
    response_message, ok := serialization.deserialize_pulse_message(buffer[:bytes_read])
    if !ok {
        // Log deserialization error
        tracing.write_trace_event(
            .ERROR,
            "pulse_client",
            "Failed to deserialize handshake response",
            trace_id
        )
        return protocol.Pulse_Message{}, .SERIALIZATION_ERROR
    }

    // Log successful handshake
    tracing.write_trace_event(
        .INFO,
        "pulse_client",
        "Handshake completed successfully",
        trace_id
    )

    return response_message, .NONE
}

// Modify main function to initialize tracing
main :: proc() {
    // Initialize trace registry
    tracing.init_trace_registry()

    // Add console trace writer
    tracing.add_trace_writer(protocol.Trace_Writer{
        write = cast(proc(^protocol.Trace_Event))tracing.console_trace_writer,
    })

    // Add file trace writer
    file_writer := tracing.create_file_trace_writer("pulse_client_traces.log")
    tracing.add_trace_writer(protocol.Trace_Writer{
        write = cast(proc(^protocol.Trace_Event))tracing.file_trace_writer_proc,
    })

    // Create client configuration
    client_metadata := protocol.create_service_metadata(
        "example_client",
        "0.1.0",
        "localhost",
        9090
    )

    config := Client_Config{
        server_host = "127.0.0.1",
        server_port = 8080,
        service_metadata = client_metadata,
    }

    // Log client startup
    tracing.write_trace_event(
        .INFO,
        "pulse_client",
        "Client application starting"
    )

    // Create client
    client, err := create_client(config)
    if err != .NONE {
        tracing.write_trace_event(
            .CRITICAL,
            "pulse_client",
            fmt.tprintf("Failed to create client: %v", err)
        )
        os.exit(1)
    }
    defer disconnect(client)

    // Connect to server
    connect_err := connect(client)
    if connect_err != .NONE {
        tracing.write_trace_event(
            .ERROR,
            "pulse_client",
            fmt.tprintf("Connection failed: %v", connect_err)
        )
        os.exit(1)
    }

    // Perform handshake
    handshake_response, handshake_err := handshake(client)
    if handshake_err != .NONE {
        tracing.write_trace_event(
            .ERROR,
            "pulse_client",
            fmt.tprintf("Handshake failed: %v", handshake_err)
        )
        os.exit(1)
    }

    // Log handshake response
    tracing.write_trace_event(
        .INFO,
        "pulse_client",
        fmt.tprintf("Handshake response: %s", string(handshake_response.payload))
    )
}
