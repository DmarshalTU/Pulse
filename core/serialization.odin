package pulse_protocol

import "core:fmt"
import "core:strings"
import "core:slice"
import "core:encoding/endian"
import "core:os"
import "core:encoding/uuid"
import "core:time"

// Binary Serializer
Binary_Serializer :: struct {
    buffer: [dynamic]u8,
    error: Serialization_Error,
}

// Create a new serializer
create_serializer :: proc() -> Binary_Serializer {
    return Binary_Serializer{
        buffer = make([dynamic]u8),
        error = .NONE,
    }
}

// Write various types to the serializer
write_u8 :: proc(s: ^Binary_Serializer, value: u8) {
    append(&s.buffer, value)
}

write_u16 :: proc(s: ^Binary_Serializer, value: u16) {
    bytes := endian.marshal_u16(value, .Big)
    append(&s.buffer, bytes[0], bytes[1])
}

write_u32 :: proc(s: ^Binary_Serializer, value: u32) {
    bytes := endian.marshal_u32(value, .Big)
    append(&s.buffer, bytes[0], bytes[1], bytes[2], bytes[3])
}

write_u64 :: proc(s: ^Binary_Serializer, value: u64) {
    bytes := endian.marshal_u64(value, .Big)
    append(&s.buffer, bytes)
}

write_string :: proc(s: ^Binary_Serializer, value: string) {
    write_u32(s, u32(len(value)))
    append(&s.buffer, value[:])
}

write_uuid :: proc(s: ^Binary_Serializer, value: uuid.UUID) {
    append(&s.buffer, value[:])
}

write_time :: proc(s: ^Binary_Serializer, value: time.Time) {
    write_u64(s, u64(time.to_unix_nano(value)))
}

// Binary Deserializer
Binary_Deserializer :: struct {
    buffer: []u8,
    offset: int,
    error: Serialization_Error,
}

// Create a new deserializer
create_deserializer :: proc(data: []u8) -> Binary_Deserializer {
    return Binary_Deserializer{
        buffer = data,
        offset = 0,
        error = .NONE,
    }
}

// Read various types from the deserializer
read_u8 :: proc(d: ^Binary_Deserializer) -> u8 {
    if d.offset >= len(d.buffer) {
        d.error = .BUFFER_OVERFLOW
        return 0
    }
    value := d.buffer[d.offset]
    d.offset += 1
    return value
}

read_u16 :: proc(d: ^Binary_Deserializer) -> u16 {
    if d.offset + 1 >= len(d.buffer) {
        d.error = .BUFFER_OVERFLOW
        return 0
    }
    value := endian.unmarshal_u16(d.buffer[d.offset:], .Big)
    d.offset += 2
    return value
}

read_u32 :: proc(d: ^Binary_Deserializer) -> u32 {
    if d.offset + 3 >= len(d.buffer) {
        d.error = .BUFFER_OVERFLOW
        return 0
    }
    value := endian.unmarshal_u32(d.buffer[d.offset:], .Big)
    d.offset += 4
    return value
}

read_u64 :: proc(d: ^Binary_Deserializer) -> u64 {
    if d.offset + 7 >= len(d.buffer) {
        d.error = .BUFFER_OVERFLOW
        return 0
    }
    value := endian.unmarshal_u64(d.buffer[d.offset:], .Big)
    d.offset += 8
    return value
}

read_string :: proc(d: ^Binary_Deserializer) -> string {
    length := read_u32(d)
    if d.offset + int(length) > len(d.buffer) {
        d.error = .BUFFER_OVERFLOW
        return ""
    }
    value := string(d.buffer[d.offset:d.offset+int(length)])
    d.offset += int(length)
    return value
}

read_uuid :: proc(d: ^Binary_Deserializer) -> uuid.UUID {
    if d.offset + 16 > len(d.buffer) {
        d.error = .BUFFER_OVERFLOW
        return uuid.nil
    }
    value: uuid.UUID
    copy(value[:], d.buffer[d.offset:d.offset+16])
    d.offset += 16
    return value
}

read_time :: proc(d: ^Binary_Deserializer) -> time.Time {
    nano_seconds := read_u64(d)
    return time.from_unix_nano(i64(nano_seconds))
}

// Serialize Pulse Message
serialize_pulse_message :: proc(msg: ^Pulse_Message) -> []u8 {
    s := create_serializer()

    // Write protocol version
    write_u16(&s, msg.version)

    // Write message type
    write_u8(&s, u8(msg.message_type))

    // Serialize Trace Context
    write_uuid(&s, msg.trace.trace_id)
    write_uuid(&s, msg.trace.span_id)
    write_uuid(&s, msg.trace.parent_span_id)
    write_time(&s, msg.trace.start_time)
    write_time(&s, msg.trace.end_time)
    write_string(&s, msg.trace.service_name)
    write_string(&s, msg.trace.service_version)

    // Serialize Source Service Metadata
    write_uuid(&s, msg.source_service.id)
    write_string(&s, msg.source_service.name)
    write_string(&s, msg.source_service.version)
    write_string(&s, msg.source_service.host)
    write_u32(&s, u32(msg.source_service.port))
    write_u8(&s, u8(msg.source_service.status))
    write_time(&s, msg.source_service.last_heartbeat)
    write_u32(&s, u32(msg.source_service.cpu_cores * 100))
    write_u32(&s, msg.source_service.memory_mb)

    // Serialize Target Service Metadata (similar to source)
    write_uuid(&s, msg.target_service.id)
    write_string(&s, msg.target_service.name)
    write_string(&s, msg.target_service.version)
    write_string(&s, msg.target_service.host)
    write_u32(&s, u32(msg.target_service.port))
    write_u8(&s, u8(msg.target_service.status))
    write_time(&s, msg.target_service.last_heartbeat)
    write_u32(&s, u32(msg.target_service.cpu_cores * 100))
    write_u32(&s, msg.target_service.memory_mb)

    // Serialize Payload
    write_u32(&s, u32(len(msg.payload)))
    append(&s.buffer, msg.payload)

    // Serialize Metadata
    write_u32(&s, u32(len(msg.metadata)))
    for key, value in msg.metadata {
        write_string(&s, key)
        write_string(&s, value)
    }

    return s.buffer[:]
}

// Deserialize Pulse Message
deserialize_pulse_message :: proc(data: []u8) -> (Pulse_Message, bool) {
    d := create_deserializer(data)
    msg: Pulse_Message

    // Read protocol version
    msg.version = read_u16(&d)

    // Read message type
    msg.message_type = Message_Type(read_u8(&d))

    // Deserialize Trace Context
    msg.trace.trace_id = read_uuid(&d)
    msg.trace.span_id = read_uuid(&d)
    msg.trace.parent_span_id = read_uuid(&d)
    msg.trace.start_time = read_time(&d)
    msg.trace.end_time = read_time(&d)
    msg.trace.service_name = read_string(&d)
    msg.trace.service_version = read_string(&d)

    // Deserialize Source Service Metadata
    msg.source_service.id = read_uuid(&d)
    msg.source_service.name = read_string(&d)
    msg.source_service.version = read_string(&d)
    msg.source_service.host = read_string(&d)
    msg.source_service.port = int(read_u32(&d))
    msg.source_service.status = Service_Status(read_u8(&d))
    msg.source_service.last_heartbeat = read_time(&d)
    msg.source_service.cpu_cores = f32(read_u32(&d)) / 100.0
    msg.source_service.memory_mb = read_u32(&d)

    // Deserialize Target Service Metadata
    msg.target_service.id = read_uuid(&d)
    msg.target_service.name = read_string(&d)
    msg.target_service.version = read_string(&d)
    msg.target_service.host = read_string(&d)
    msg.target_service.port = int(read_u32(&d))
    msg.target_service.status = Service_Status(read_u8(&d))
    msg.target_service.last_heartbeat = read_time(&d)
    msg.target_service.cpu_cores = f32(read_u32(&d)) / 100.0
    msg.target_service.memory_mb = read_u32(&d)

    // Deserialize Payload
    payload_length := read_u32(&d)
    msg.payload = make([]u8, payload_length)
    copy(msg.payload, d.buffer[d.offset:d.offset+int(payload_length)])
    d.offset += int(payload_length)

    // Deserialize Metadata
    metadata_count := read_u32(&d)
    msg.metadata = make(map[string]string)
    for _ in 0..<metadata_count {
        key := read_string(&d)
        value := read_string(&d)
        msg.metadata[key] = value
    }

    return msg, d.error == .NONE
}

// Example usage and testing
test_serialization :: proc() {
    // Create source and target services
    source_service := create_service_metadata(
        "client_service",
        "1.0.0",
        "localhost",
        8080
    )

    target_service := create_service_metadata(
        "target_service",
        "1.0.0",
        "localhost",
        9090
    )

    // Create a sample message
    original_msg := create_pulse_message(
        .REQUEST,
        source_service,
        target_service,
        []u8("Hello, Pulse Protocol!")
    )

    // Add some metadata
    original_msg.metadata["key1"] = "value1"
    original_msg.metadata["key2"] = "value2"

    // Serialize the message
    serialized_data := serialize_pulse_message(&original_msg)

    // Deserialize the message
    deserialized_msg, ok := deserialize_pulse_message(serialized_data)

    if !ok {
        fmt.eprintln("Deserialization failed")
        return
    }

    // Compare original and deserialized messages
    fmt.println("Serialization Test:")
    fmt.println("Original Message Version:", original_msg.version)
    fmt.println("Deserialized Message Version:", deserialized_msg.version)
    fmt.println("Payload Match:", string(original_msg.payload) == string(deserialized_msg.payload))
}

main :: proc() {
    test_serialization()
}
