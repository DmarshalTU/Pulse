// tracing.odin
package pulse_protocol

import "core:fmt"
import "core:time"
import "core:sync"
import "core:strings"
import "core:slice"
import "core:os"

// Trace Levels
Trace_Level :: enum {
    DEBUG,
    INFO,
    WARN,
    ERROR,
    CRITICAL,
}

// Trace Event
Trace_Event :: struct {
    timestamp: time.Time,
    level: Trace_Level,
    service_name: string,
    message: string,
    trace_id: string,
    span_id: string,
    parent_span_id: string,
}

// Trace Writer Interface
Trace_Writer :: struct {
    write: proc(event: ^Trace_Event),
}

// Global Trace Registry
Trace_Registry :: struct {
    events: [dynamic]Trace_Event,
    writers: [dynamic]Trace_Writer,
    mutex: sync.Mutex,
}

// Global trace registry
global_trace_registry: Trace_Registry

// Initialize trace registry
init_trace_registry :: proc() {
    global_trace_registry = Trace_Registry{
        events = make([dynamic]Trace_Event),
        writers = make([dynamic]Trace_Writer),
    }
}

// Add trace writer
add_trace_writer :: proc(writer: Trace_Writer) {
    sync.mutex_lock(&global_trace_registry.mutex)
    defer sync.mutex_unlock(&global_trace_registry.mutex)

    append(&global_trace_registry.writers, writer)
}

// Write trace event
write_trace_event :: proc(
    level: Trace_Level,
    service_name: string,
    message: string,
    trace_id: string = "",
    span_id: string = "",
    parent_span_id: string = "",
) {
    sync.mutex_lock(&global_trace_registry.mutex)
    defer sync.mutex_unlock(&global_trace_registry.mutex)

    event := Trace_Event{
        timestamp = time.now(),
        level = level,
        service_name = service_name,
        message = message,
        trace_id = trace_id,
        span_id = span_id,
        parent_span_id = parent_span_id,
    }

    // Store event
    append(&global_trace_registry.events, event)

    // Notify writers
    for writer in global_trace_registry.writers {
        writer.write(&event)
    }
}

// Console trace writer
console_trace_writer :: proc(event: ^Trace_Event) {
    fmt.printf(
        "[%v] %v: %s | Trace: %s, Span: %s\n",
        event.timestamp,
        event.level,
        event.message,
        event.trace_id,
        event.span_id,
    )
}

// File trace writer
File_Trace_Writer :: struct {
    file_path: string,
    file: ^os.Handle,
}

create_file_trace_writer :: proc(file_path: string) -> File_Trace_Writer {
    file, open_err := os.open(file_path, os.O_WRONLY | os.O_CREATE | os.O_APPEND)
    if open_err != os.ERROR_NONE {
        fmt.eprintln("Failed to open trace file:", file_path)
        return File_Trace_Writer{}
    }

    return File_Trace_Writer{
        file_path = file_path,
        file = &file,
    }
}

file_trace_writer_proc :: proc(writer: ^File_Trace_Writer, event: ^Trace_Event) {
    if writer.file == nil {
        return
    }

    trace_line := fmt.tprintf(
        "[%v] %v: %s | Trace: %s, Span: %s\n",
        event.timestamp,
        event.level,
        event.message,
        event.trace_id,
        event.span_id,
    )

    os.write(writer.file^, []u8(trace_line))
}

// Example tracing usage
example_tracing :: proc() {
    // Initialize trace registry
    init_trace_registry()

    // Add console writer
    add_trace_writer(Trace_Writer{
        write = cast(proc(^Trace_Event))console_trace_writer,
    })

    // Add file writer
    file_writer := create_file_trace_writer("pulse_protocol_traces.log")
    add_trace_writer(Trace_Writer{
        write = cast(proc(^Trace_Event))file_trace_writer_proc,
    })

    // Write some trace events
    write_trace_event(.INFO, "pulse_server", "Server started")
    write_trace_event(.DEBUG, "pulse_client", "Client connection established", "trace-123", "span-456")
    write_trace_event(.ERROR, "pulse_service", "Connection failed", "trace-789", "span-101")
}

main :: proc() {
    example_tracing()
}
