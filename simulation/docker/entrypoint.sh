#!/bin/bash
# Entrypoint for FAST-LIVO2 + PX4 Gazebo simulation container
set -e

source /opt/ros/noetic/setup.bash
source /root/catkin_ws/devel/setup.bash
export GAZEBO_MODEL_PATH="/root/catkin_ws/src/FAST-LIVO2/simulation/models:${GAZEBO_MODEL_PATH:-}"

# If first argument is "sim", launch the full simulation stack
if [ "$1" = "sim" ]; then
    echo "============================================"
    echo "  FAST-LIVO2 + PX4 Gazebo Rover Simulation"
    echo "============================================"

    # Display/VNC setup:
    #   GAZEBO_GUI=true  → host X11 (Linux / XQuartz) via $DISPLAY
    #   GAZEBO_GUI=vnc   → Xvfb + x11vnc + noVNC on http://localhost:6080
    #   GAZEBO_GUI=false → Xvfb only (for headless camera rendering)
    if [ "${GAZEBO_GUI:-true}" = "vnc" ]; then
        echo "Starting virtual display + VNC + noVNC..."
        rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
        Xvfb :99 -screen 0 1280x800x24 -ac +extension GLX +render -noreset &
        export DISPLAY=:99
        sleep 2
        fluxbox >/tmp/fluxbox.log 2>&1 &
        x11vnc -display :99 -forever -shared -nopw -rfbport 5900 -quiet >/tmp/x11vnc.log 2>&1 &
        websockify --web=/usr/share/novnc/ 6080 localhost:5900 >/tmp/novnc.log 2>&1 &
        sleep 1
        echo ""
        echo "================================================================"
        echo "  Gazebo GUI available in your browser at:"
        echo "    http://localhost:6080/vnc.html?autoconnect=1&resize=scale"
        echo "================================================================"
        echo ""
        GAZEBO_GUI=true  # tell roslaunch to start gzclient
    elif [ "${GAZEBO_GUI:-true}" = "false" ] && [ -z "$DISPLAY" ]; then
        echo "Starting Xvfb for headless camera rendering..."
        rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
        Xvfb :99 -screen 0 1024x768x24 -ac +extension GLX +render -noreset &
        export DISPLAY=:99
        sleep 2
    fi

    # Start PX4 SITL in background with rover airframe.
    # We invoke the px4 binary directly (not `make px4_sitl ...`) because
    # the make/sh wrapper chain causes px4_daemon poll() to fail with EINTR
    # when the shell receives SIGCHLD, leaving rcS stuck at `px4-param select`.
    # setsid + stdin redirected from /dev/null fully detaches from the tty.
    echo "[1/2] Starting PX4 SITL (rover airframe)..."
    PX4_BUILD=/root/PX4-Autopilot/build/px4_sitl_default
    if [ ! -x "$PX4_BUILD/bin/px4" ]; then
        echo "Building PX4 binary (first run)..."
        cd /root/PX4-Autopilot && DONT_RUN=1 make px4_sitl none_rover > /tmp/px4_build.log 2>&1
    fi
    mkdir -p "$PX4_BUILD/tmp"
    cd "$PX4_BUILD/tmp"
    PX4_SIM_MODEL=rover HEADLESS=1 NO_PXH=1 \
        setsid "$PX4_BUILD/bin/px4" \
            -d "$PX4_BUILD/etc" \
            -s etc/init.d-posix/rcS \
            -t /root/PX4-Autopilot/test_data \
            < /dev/null > /tmp/px4.log 2>&1 &
    PX4_PID=$!

    # Wait for PX4 MAVLink instances to come up (checks UDP port 14540)
    echo "Waiting for PX4 SITL MAVLink (udp/14540)..."
    for i in $(seq 1 60); do
        if ss -uln 2>/dev/null | grep -q ":14540"; then
            echo "PX4 MAVLink up after ${i}s"
            break
        fi
        sleep 1
    done

    if ! kill -0 "$PX4_PID" 2>/dev/null; then
        echo "ERROR: PX4 SITL failed to start. Last 30 lines of /tmp/px4.log:"
        tail -30 /tmp/px4.log
        exit 1
    fi
    echo "PX4 SITL running (target: none_rover)"

    # Launch ROS stack
    echo "[2/2] Launching Gazebo + MAVROS + FAST-LIVO2..."
    echo ""
    echo "To drive the rover, exec into the container:"
    echo "  docker exec -it fast-livo2-sim bash"
    echo "  rostopic pub /rover/cmd_vel geometry_msgs/Twist \"linear: {x: 0.5}\" -r 10"
    echo ""

    # World defaults to livo2_test.world; override via $WORLD env (e.g. "forest").
    WORLD_NAME=${WORLD:-livo2_test}
    WORLD_PATH=/root/catkin_ws/src/FAST-LIVO2/simulation/worlds/${WORLD_NAME}.world
    echo "Using world: ${WORLD_PATH}"
    roslaunch fast_livo gazebo_px4_rover.launch gui:=${GAZEBO_GUI:-true} world:=${WORLD_PATH}

elif [ "$1" = "teleop" ]; then
    echo "Starting teleop keyboard control..."
    echo "Use WASD keys to drive the rover."
    rosrun teleop_twist_keyboard teleop_twist_keyboard.py cmd_vel:=/rover/cmd_vel

else
    exec "$@"
fi
