// service_registry.odin
package pulse_protocol

import "core:fmt"
import "core:time"
import "core:sync"
import "core:slice"
import "core:uuid"

// Service Registry Configuration
SERVICE_REGISTRY_CLEANUP_INTERVAL :: 5 * time.Minute
SERVICE_REGISTRY_TIMEOUT :: 10 * time.Minute

// Service Registry Structure
Service_Registry :: struct {
    services: map[uuid.UUID]Registered_Service,
    mutex: sync.Mutex,
}

// Registered Service Details
Registered_Service :: struct {
    metadata: Service_Metadata,
    registered_at: time.Time,
    last_heartbeat: time.Time,
}

// Create a new Service Registry
create_service_registry :: proc() -> ^Service_Registry {
    registry := new(Service_Registry)
    registry.services = make(map[uuid.UUID]Registered_Service)
    return registry
}

// Register a new service
register_service :: proc(
    registry: ^Service_Registry,
    service_metadata: Service_Metadata
) -> uuid.UUID {
    sync.mutex_lock(&registry.mutex)
    defer sync.mutex_unlock(&registry.mutex)

    // Use service's existing ID or generate a new one
    service_id := service_metadata.id

    registered_service := Registered_Service{
        metadata = service_metadata,
        registered_at = time.now(),
        last_heartbeat = time.now(),
    }

    registry.services[service_id] = registered_service
    return service_id
}

// Update service heartbeat
update_service_heartbeat :: proc(
    registry: ^Service_Registry,
    service_id: uuid.UUID
) -> bool {
    sync.mutex_lock(&registry.mutex)
    defer sync.mutex_unlock(&registry.mutex)

    if service_ptr, ok := &registry.services[service_id]; ok {
        service_ptr.last_heartbeat = time.now()
        service_ptr.metadata.status = .HEALTHY
        return true
    }
    return false
}

// Find service by ID
find_service_by_id :: proc(
    registry: ^Service_Registry,
    service_id: uuid.UUID
) -> (Service_Metadata, bool) {
    sync.mutex_lock(&registry.mutex)
    defer sync.mutex_unlock(&registry.mutex)

    if registered_service, ok := registry.services[service_id]; ok {
        return registered_service.metadata, true
    }
    return Service_Metadata{}, false
}

// Find services by name
find_services_by_name :: proc(
    registry: ^Service_Registry,
    service_name: string
) -> []Service_Metadata {
    sync.mutex_lock(&registry.mutex)
    defer sync.mutex_unlock(&registry.mutex)

    matching_services: [dynamic]Service_Metadata

    for _, registered_service in registry.services {
        if registered_service.metadata.name == service_name {
            append(&matching_services, registered_service.metadata)
        }
    }

    return matching_services[:]
}

// Remove inactive services
cleanup_inactive_services :: proc(registry: ^Service_Registry) {
    sync.mutex_lock(&registry.mutex)
    defer sync.mutex_unlock(&registry.mutex)

    current_time := time.now()
    inactive_services: [dynamic]uuid.UUID

    for service_id, registered_service in registry.services {
        if time.diff(registered_service.last_heartbeat, current_time) > SERVICE_REGISTRY_TIMEOUT {
            registered_service.metadata.status = .OFFLINE
            append(&inactive_services, service_id)
        }
    }

    // Remove inactive services
    for service_id in inactive_services {
        delete_key(&registry.services, service_id)
    }
}

// List all registered services
list_services :: proc(registry: ^Service_Registry) -> []Service_Metadata {
    sync.mutex_lock(&registry.mutex)
    defer sync.mutex_unlock(&registry.mutex)

    services: [dynamic]Service_Metadata
    for _, registered_service in registry.services {
        append(&services, registered_service.metadata)
    }

    return services[:]
}

// Example usage and testing
test_service_registry :: proc() {
    // Create a new service registry
    registry := create_service_registry()

    // Create some sample services
    service1 := create_service_metadata(
        "web_service",
        "1.0.0",
        "localhost",
        8080
    )

    service2 := create_service_metadata(
        "database_service",
        "2.0.0",
        "localhost",
        5432
    )

    // Register services
    service1_id := register_service(registry, service1)
    service2_id := register_service(registry, service2)

    // Update heartbeats
    update_service_heartbeat(registry, service1_id)
    update_service_heartbeat(registry, service2_id)

    // Find services
    found_service, found := find_service_by_id(registry, service1_id)
    if found {
        fmt.println("Found Service:", found_service.name)
    }

    // List all services
    all_services := list_services(registry)
    fmt.println("Registered Services:")
    for service in all_services {
        fmt.printf("- %s (v%s) at %s:%d\n",
            service.name,
            service.version,
            service.host,
            service.port
        )
    }

    // Cleanup inactive services
    cleanup_inactive_services(registry)
}

main :: proc() {
    test_service_registry()
}
