#!/bin/bash
# =============================================================================
# Run FAST-LIVO2 + PX4 SITL + Gazebo Rover via Docker
#
# This script works on macOS (and Linux). It builds and runs a Docker container
# with the full ROS Noetic + PX4 + Gazebo + FAST-LIVO2 stack.
#
# Prerequisites:
#   - Docker Desktop (macOS) or Docker Engine (Linux)
#   - XQuartz (macOS, for Gazebo GUI): brew install --cask xquartz
#     After installing XQuartz: open XQuartz → Preferences → Security →
#     check "Allow connections from network clients", then restart.
#
# Usage:
#   ./scripts/run_gazebo_px4_rover.sh              # build + run with GUI
#   ./scripts/run_gazebo_px4_rover.sh --headless    # run without GUI
#   ./scripts/run_gazebo_px4_rover.sh --build-only  # just build the image
#   ./scripts/run_gazebo_px4_rover.sh --teleop      # start teleop controller
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$REPO_DIR/simulation/docker/docker-compose.yml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Check Docker ─────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    echo -e "${RED}ERROR: Docker not found. Install Docker Desktop first.${NC}"
    echo "  macOS: https://docs.docker.com/desktop/install/mac-install/"
    exit 1
fi

if ! docker info &>/dev/null 2>&1; then
    echo -e "${RED}ERROR: Docker daemon not running. Start Docker Desktop.${NC}"
    exit 1
fi

# ── macOS X11 forwarding setup ───────────────────────────────────────────────
setup_x11_macos() {
    if [[ "$(uname)" == "Darwin" ]]; then
        if ! command -v xquartz &>/dev/null && [ ! -d "/Applications/Utilities/XQuartz.app" ]; then
            echo -e "${YELLOW}WARNING: XQuartz not found. Gazebo GUI won't work.${NC}"
            echo "  Install with: brew install --cask xquartz"
            echo "  Running headless instead."
            export GAZEBO_GUI=false
            return
        fi

        # Allow X11 connections from localhost
        xhost +localhost 2>/dev/null || true
        export DISPLAY=host.docker.internal:0
    fi
}

# ── Commands ─────────────────────────────────────────────────────────────────
case "${1:-}" in
    --build-only)
        echo -e "${CYAN}Building Docker image (this takes ~20-30 min first time)...${NC}"
        docker compose -f "$COMPOSE_FILE" build sim
        echo -e "${GREEN}Build complete! Run without --build-only to start the simulation.${NC}"
        ;;

    --headless)
        echo -e "${CYAN}Starting simulation (headless, no GUI)...${NC}"
        docker compose -f "$COMPOSE_FILE" --profile headless up sim-headless
        ;;

    --teleop)
        echo -e "${CYAN}Starting teleop keyboard controller...${NC}"
        echo -e "${YELLOW}Use WASD keys to drive. Press q to quit.${NC}"
        docker compose -f "$COMPOSE_FILE" --profile tools run --rm teleop
        ;;

    --stop)
        echo -e "${YELLOW}Stopping simulation...${NC}"
        docker compose -f "$COMPOSE_FILE" down
        echo -e "${GREEN}Stopped.${NC}"
        ;;

    --shell)
        echo -e "${CYAN}Opening shell in running container...${NC}"
        docker exec -it fast-livo2-sim bash
        ;;

    --help|-h)
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  (none)         Build (if needed) and run simulation with Gazebo GUI"
        echo "  --headless     Run without Gazebo GUI"
        echo "  --build-only   Build the Docker image without running"
        echo "  --teleop       Start teleop keyboard controller (sim must be running)"
        echo "  --stop         Stop the simulation"
        echo "  --shell        Open a bash shell in the running container"
        echo "  --help         Show this help"
        ;;

    *)
        setup_x11_macos

        echo -e "${CYAN}============================================${NC}"
        echo -e "${CYAN}  FAST-LIVO2 + PX4 Gazebo Rover Simulation ${NC}"
        echo -e "${CYAN}============================================${NC}"
        echo ""
        echo -e "${YELLOW}Building Docker image (first run takes ~20-30 min)...${NC}"
        echo ""

        docker compose -f "$COMPOSE_FILE" up --build sim

        ;;
esac
