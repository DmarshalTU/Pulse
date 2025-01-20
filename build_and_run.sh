#!/bin/bash

# Set color output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Project directories
PROTOCOL_DIR="core"
SERVER_DIR="server"
CLIENT_DIR="client"
FRONTEND_DIR="frontend"
REGISTRY_DIR="registry"

# Build function
build_component() {
    local dir=$1
    local component=$2

    echo -e "${GREEN}Building $component...${NC}"
    cd "$dir"
    odin build "$component.odin" -file
    build_result=$?
    cd ..

    if [ $build_result -ne 0 ]; then
        echo -e "${RED}Failed to build $component${NC}"
        exit 1
    fi
}

# Clean previous builds
clean() {
    echo -e "${GREEN}Cleaning previous builds...${NC}"
    # Modified to use more portable find command
    find . -type f -perm +111 -delete
}

# Build all components
build_all() {
    # clean
    build_component "$PROTOCOL_DIR" "protocol"
    build_component "$PROTOCOL_DIR" "serialization"
    build_component "$PROTOCOL_DIR" "tracing"
    build_component "$REGISTRY_DIR" "service_registry"
    build_component "$SERVER_DIR" "server"
    build_component "$CLIENT_DIR" "client"
    build_component "$FRONTEND_DIR" "frontend"
}

# Run components
run_components() {
    echo -e "${GREEN}Starting Pulse Protocol Components...${NC}"

    # Start server in background
    echo -e "${GREEN}Starting Pulse Protocol Server...${NC}"
    ./server &
    SERVER_PID=$!
    sleep 2

    # Start frontend in another background process
    echo -e "${GREEN}Starting Frontend...${NC}"
    ./frontend &
    FRONTEND_PID=$!
    sleep 2

    echo -e "${GREEN}Pulse Protocol is now running${NC}"
    echo -e "${GREEN}Server running on port 8080${NC}"
    echo -e "${GREEN}Frontend running on port 9000${NC}"

    # Trap to ensure clean shutdown
    trap 'kill $SERVER_PID $FRONTEND_PID' SIGINT SIGTERM

    # Wait for background processes
    wait
}

# Main script execution
main() {
    build_all
    run_components
}

# Execute main function
main
