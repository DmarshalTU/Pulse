// frontend.odin (with tracing)
package pulse_frontend

import "core:fmt"
import "core:net"
import "core:os"
import "core:uuid"

import "../core/protocol"
import "../core/tracing"

// Web Server Configuration
Web_Server_Config :: struct {
    host: string,
    port: int,
}

// HTTP Request Structure
HTTP_Request :: struct {
    method: string,
    path: string,
    headers: map[string]string,
    body: string,
}

// HTTP Response Structure
HTTP_Response :: struct {
    status_code: int,
    headers: map[string]string,
    body: string,
}

// Parse HTTP Request
parse_http_request :: proc(request_data: []u8) -> (HTTP_Request, bool) {
    request_str := string(request_data)
    lines := strings.split(request_str, "\r\n")

    if len(lines) < 1 {
        return HTTP_Request{}, false
    }

    // Parse first line (method and path)
    first_line_parts := strings.split(lines[0], " ")
    if len(first_line_parts) < 3 {
        return HTTP_Request{}, false
    }

    request := HTTP_Request{
        method = first_line_parts[0],
        path = first_line_parts[1],
        headers = make(map[string]string),
    }

    // Parse headers
    for i := 1; i < len(lines); i += 1 {
        if lines[i] == "" {
            // Empty line separates headers from body
            if i+1 < len(lines) {
                request.body = lines[i+1]
            }
            break
        }

        header_parts := strings.split(lines[i], ": ")
        if len(header_parts) == 2 {
            request.headers[header_parts[0]] = header_parts[1]
        }
    }

    return request, true
}

// Generate HTTP Response
generate_http_response :: proc(response: HTTP_Response) -> []u8 {
    status_text := "OK"
    match response.status_code {
    case 200: status_text = "OK"
    case 404: status_text = "Not Found"
    case 500: status_text = "Internal Server Error"
    }

    headers_str := strings.builder_make()
    defer strings.builder_destroy(&headers_str)

    strings.write_string(&headers_str, fmt.tprintf("HTTP/1.1 %d %s\r\n", response.status_code, status_text))
    strings.write_string(&headers_str, "Content-Type: text/html; charset=utf-8\r\n")
    strings.write_string(&headers_str, fmt.tprintf("Content-Length: %d\r\n", len(response.body)))
    strings.write_string(&headers_str, "Connection: close\r\n")
    strings.write_string(&headers_str, "\r\n")

    response_str := strings.builder_make()
    defer strings.builder_destroy(&response_str)

    strings.write_string(&response_str, strings.to_string(headers_str))
    strings.write_string(&response_str, response.body)

    return []u8(strings.to_string(response_str))
}

// Frontend HTML
get_frontend_html :: proc() -> string {
    return `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Pulse Protocol Frontend</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        h1 { color: #333; }
        button { margin: 10px 0; }
        #output { border: 1px solid #ddd; padding: 10px; white-space: pre-wrap; }
    </style>
</head>
<body>
    <h1>Pulse Protocol Demo</h1>

    <div>
        <h2>Service Discovery</h2>
        <input type="text" id="serviceName" placeholder="Service Name">
        <button onclick="discoverServices()">Discover Services</button>
    </div>

    <div>
        <h2>Send Request</h2>
        <textarea id="requestPayload" placeholder="Request Payload"></textarea>
        <button onclick="sendRequest()">Send Request</button>
    </div>

    <h2>Output</h2>
    <div id="output"></div>

    <script>
        function log(message) {
            const output = document.getElementById('output');
            output.textContent += message + '\n';
        }

        function discoverServices() {
            const serviceName = document.getElementById('serviceName').value;
            fetch('/discover-services', {
                method: 'POST',
                body: serviceName
            })
            .then(response => response.text())
            .then(data => log('Service Discovery: ' + data))
            .catch(error => log('Error: ' + error));
        }

        function sendRequest() {
            const payload = document.getElementById('requestPayload').value;
            fetch('/send-request', {
                method: 'POST',
                body: payload
            })
            .then(response => response.text())
            .then(data => log('Request Response: ' + data))
            .catch(error => log('Error: ' + error));
        }
    </script>
</body>
</html>
    `
}

// Handle client requests
handle_request :: proc(request: HTTP_Request) -> HTTP_Response {
    // Create Pulse Protocol client
    client_metadata := protocol.create_service_metadata(
        "frontend_client",
        "0.1.0",
        "localhost",
        9090
    )

    client_config := pulse_client.Client_Config{
        server_host = "127.0.0.1",
        server_port = 8080,
        service_metadata = client_metadata,
    }

    client, client_err := pulse_client.create_client(client_config)
    if client_err != .NONE {
        return HTTP_Response{
            status_code = 500,
            body = "Failed to create client",
        }
    }
    defer pulse_client.disconnect(client)

    // Connect to server
    connect_err := pulse_client.connect(client)
    if connect_err != .NONE {
        return HTTP_Response{
            status_code = 500,
            body = "Connection failed",
        }
    }

    // Perform handshake
    _, handshake_err := pulse_client.handshake(client)
    if handshake_err != .NONE {
        return HTTP_Response{
            status_code = 500,
            body = "Handshake failed",
        }
    }

    // Route requests
    switch request.path {
    case "/":
        return HTTP_Response{
            status_code = 200,
            body = get_frontend_html(),
        }

    case "/discover-services":
        response, discover_err := pulse_client.discover_services(client, request.body)
        if discover_err != .NONE {
            return HTTP_Response{
                status_code = 500,
                body = "Service discovery failed",
            }
        }
        return HTTP_Response{
            status_code = 200,
            body = string(response.payload),
        }

    case "/send-request":
        response, request_err := pulse_client.send_request(client, []u8(request.body))
        if request_err != .NONE {
            return HTTP_Response{
                status_code = 500,
                body = "Request failed",
            }
        }
        return HTTP_Response{
            status_code = 200,
            body = string(response.payload),
        }

    case:
        return HTTP_Response{
            status_code = 404,
            body = "Not Found",
        }
    }
}

// Web server main loop
run_web_server :: proc(config: Web_Server_Config) -> protocol.Pulse_Error {
    // Initialize trace registry
    tracing.init_trace_registry()

    // Add console trace writer
    tracing.add_trace_writer(protocol.Trace_Writer{
        write = cast(proc(^protocol.Trace_Event))tracing.console_trace_writer,
    })

    // Add file trace writer
    file_writer := tracing.create_file_trace_writer("pulse_frontend_traces.log")
    tracing.add_trace_writer(protocol.Trace_Writer{
        write = cast(proc(^protocol.Trace_Event))tracing.file_trace_writer_proc,
    })

    // Log frontend startup
    tracing.write_trace_event(
        .INFO,
        "pulse_frontend",
        fmt.tprintf("Starting web frontend on %s:%d", config.host, config.port)
    )

    endpoint := net.Endpoint{
        address = net.parse_address(config.host),
        port = config.port,
    }

    listener, listen_err := net.listen_tcp(endpoint)
    if listen_err != nil {
        // Log server creation error
        tracing.write_trace_event(
            .CRITICAL,
            "pulse_frontend",
            fmt.tprintf("Failed to create web server: %v", listen_err)
        )
        return .NETWORK_ERROR
    }
    defer net.close(listener)

    tracing.write_trace_event(
        .INFO,
        "pulse_frontend",
        fmt.tprintf("Web Frontend running on http://%s:%d", config.host, config.port)
    )

    for {
        conn, accept_err := net.accept_tcp(listener)
        if accept_err != nil {
            // Log connection accept error
            tracing.write_trace_event(
                .ERROR,
                "pulse_frontend",
                fmt.tprintf("Connection accept error: %v", accept_err)
            )
            continue
        }

        // Generate trace ID for this connection
        trace_id := uuid.uuid_to_string(uuid.new())
        defer delete(trace_id)

        // Log connection
        tracing.write_trace_event(
            .INFO,
            "pulse_frontend",
            "Accepted new web connection",
            trace_id
        )

        // Handle connection in a goroutine
        go handle_client_connection(conn, trace_id)
    }
}

// Handle individual client connection
handle_client_connection :: proc(conn: net.TCP_Socket, trace_id: string) {
    defer net.close(conn)

    buffer: [4096]u8
    bytes_read, recv_err := net.recv_tcp(conn, buffer[:])
    if recv_err != nil {
        // Log receive error
        tracing.write_trace_event(
            .ERROR,
            "pulse_frontend",
            fmt.tprintf("Receive error: %v", recv_err),
            trace_id
        )
        return
    }

    // Parse request
    request, parse_ok := parse_http_request(buffer[:bytes_read])
    if !parse_ok {
        // Log parse error
        tracing.write_trace_event(
            .WARN,
            "pulse_frontend",
            "Failed to parse HTTP request",
            trace_id
        )

        response := generate_http_response(HTTP_Response{
            status_code = 400,
            body = "Bad Request",
        })
        net.send_tcp(conn, response)
        return
    }

    // Log request details
    tracing.write_trace_event(
        .INFO,
        "pulse_frontend",
        fmt.tprintf("Received %s request for %s", request.method, request.path),
        trace_id
    )

    // Handle request
    response := handle_request(request)
    http_response := generate_http_response(response)

    // Send response
    _, send_err := net.send_tcp(conn, http_response)
    if send_err != nil {
        // Log send error
        tracing.write_trace_event(
            .ERROR,
            "pulse_frontend",
            fmt.tprintf("Response send error: %v", send_err),
            trace_id
        )
    }
}

main :: proc() {
    config := Web_Server_Config{
        host = "127.0.0.1",
        port = 9000,
    }

    run_web_server(config)
}
