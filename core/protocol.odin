package pulse_protocol

import "core:encoding/uuid"
import "core:time"

// Protocol Version
PROTOCOL_VERSION :: 0_1_0

// Message Types
Message_Type :: enum u8 {
    HANDSHAKE,
    SERVICE_REGISTER,
    SERVICE_DISCOVER,
    REQUEST,
    RESPONSE,
    STREAM_START,
    STREAM_DATA,
    STREAM_END,
    ERROR,
}

// Service Status
Service_Status :: enum u8 {
    HEALTHY,
    STARTING,
    DEGRADED,
    MAINTENANCE,
    OFFLINE,
}

// Trace Context for distributed tracing
Trace_Context :: struct {
    trace_id: uuid.Identifier,
    span_id: uuid.Identifier,
    parent_span_id: uuid.Identifier,

    start_time: time.Time,
    end_time: time.Time,

    service_name: string,
    service_version: string,
}

// Service Metadata
Service_Metadata :: struct {
    id: uuid.Identifier,
    name: string,
    version: string,

    host: string,
    port: int,

    status: Service_Status,
    last_heartbeat: time.Time,

    // Resource information
    cpu_cores: f32,
    memory_mb: u32,
}

// Core Message Structure
Pulse_Message :: struct {
    version: u16,
    message_type: Message_Type,

    // Tracing
    trace: Trace_Context,

    // Service Information
    source_service: Service_Metadata,
    target_service: Service_Metadata,

    // Payload
    payload_length: u32,
    payload: []u8,

    // Metadata and Extensions
    metadata: map[string]string,
}

// Serialization Errors
Serialization_Error :: enum {
    NONE,
    BUFFER_OVERFLOW,
    INVALID_DATA,
    UNSUPPORTED_TYPE,
}

// Protocol Errors
Pulse_Error :: enum {
    NONE,
    SERIALIZATION_ERROR,
    NETWORK_ERROR,
    SERVICE_NOT_FOUND,
    AUTHENTICATION_FAILED,
}

// Create a new trace context
create_trace_context :: proc(service_name: string, service_version: string) -> Trace_Context {
    return Trace_Context {
        trace_id = uuid.generate_v7_basic(),
        span_id = uuid.generate_v7_basic(),
        parent_span_id = uuid.generate_v7(),
        start_time = time.now(),
        service_name = service_name,
        service_version = service_version,
    }
}

// Create a new service metadata
create_service_metadata :: proc(
    name, version, host: string,
    port: int,
    status: Service_Status = .HEALTHY
) -> Service_Metadata {
    return Service_Metadata {
        id = uuid.generate_v7_basic(),
        name = name,
        version = version,
        host = host,
        port = port,
        status = status,
        last_heartbeat = time.now(),
        cpu_cores = 1.0,
        memory_mb = 512,
    }
}

// Create a new pulse message
create_pulse_message :: proc(
    message_type: Message_Type,
    source_service, target_service: Service_Metadata,
    payload: []u8
) -> Pulse_Message {
    return Pulse_Message {
        version = PROTOCOL_VERSION,
        message_type = message_type,
        trace = create_trace_context(source_service.name, source_service.version),
        source_service = source_service,
        target_service = target_service,
        payload_length = u32(len(payload)),
        payload = payload,
        metadata = make(map[string]string),
    }
}

main :: proc() {}
