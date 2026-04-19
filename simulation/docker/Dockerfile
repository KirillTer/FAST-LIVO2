# =============================================================================
# FAST-LIVO2 + PX4 SITL + Gazebo Rover — Docker image
#
# Builds on ROS Noetic (the upstream FAST-LIVO2 is ROS1).
# Includes: PX4 SITL, MAVROS, Gazebo 11, Sophus, rpg_vikit, FAST-LIVO2.
#
# Build:  docker build -t fast-livo2-sim simulation/docker/
# Run:    docker compose -f simulation/docker/docker-compose.yml up
# =============================================================================
FROM osrf/ros:noetic-desktop-full

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-c"]

# ── System dependencies ──────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    git wget curl python3-pip python3-catkin-tools \
    ros-noetic-mavros ros-noetic-mavros-extras \
    ros-noetic-gazebo-ros ros-noetic-gazebo-ros-pkgs \
    ros-noetic-gazebo-plugins \
    ros-noetic-velodyne-gazebo-plugins \
    ros-noetic-velodyne-description \
    ros-noetic-image-transport ros-noetic-cv-bridge \
    ros-noetic-pcl-conversions ros-noetic-pcl-ros \
    ros-noetic-tf ros-noetic-tf2-ros \
    ros-noetic-teleop-twist-keyboard \
    libpcl-dev libeigen3-dev libopencv-dev libboost-thread-dev \
    libfmt-dev \
    xvfb mesa-utils libgl1-mesa-dri net-tools iproute2 \
    x11vnc novnc websockify fluxbox \
    && rm -rf /var/lib/apt/lists/*

# ── MAVROS geographiclib datasets ───────────────────────────────────────────
RUN /opt/ros/noetic/lib/mavros/install_geographiclib_datasets.sh

# ── Sophus (non-templated version required by FAST-LIVO2) ───────────────────
# Commit a621ff is required but has a GCC 9+ incompatibility with
# std::complex::real()/imag() assignment — patch it inline.
# This old Sophus doesn't install SophusConfig.cmake, so we add a FindSophus.cmake.
RUN cd /tmp && git clone https://github.com/strasdat/Sophus.git \
    && cd Sophus && git checkout a621ff \
    && sed -i 's|unit_complex_.real() = 1.;|unit_complex_ = std::complex<double>(1., 0.);|' sophus/so2.cpp \
    && sed -i '/unit_complex_.imag() = 0.;/d' sophus/so2.cpp \
    && mkdir build && cd build && cmake .. -DCMAKE_CXX_FLAGS="-Wno-error" \
    && make -j$(nproc) && make install \
    && mkdir -p /usr/local/share/cmake/Modules \
    && printf '%s\n' \
        'find_path(Sophus_INCLUDE_DIR sophus/se3.h PATHS /usr/local/include /usr/include)' \
        'find_library(Sophus_LIBRARY NAMES Sophus libSophus.so PATHS /usr/local/lib /usr/lib)' \
        'set(Sophus_INCLUDE_DIRS ${Sophus_INCLUDE_DIR})' \
        'set(Sophus_LIBRARIES ${Sophus_LIBRARY})' \
        'include(FindPackageHandleStandardArgs)' \
        'find_package_handle_standard_args(Sophus DEFAULT_MSG Sophus_INCLUDE_DIR Sophus_LIBRARY)' \
        'if(Sophus_FOUND AND NOT TARGET Sophus::Sophus)' \
        '  add_library(Sophus::Sophus UNKNOWN IMPORTED)' \
        '  set_target_properties(Sophus::Sophus PROPERTIES' \
        '    IMPORTED_LOCATION "${Sophus_LIBRARY}"' \
        '    INTERFACE_INCLUDE_DIRECTORIES "${Sophus_INCLUDE_DIR}")' \
        'endif()' \
        > /usr/local/share/cmake/Modules/FindSophus.cmake \
    && rm -rf /tmp/Sophus

# ── PX4-Autopilot (SITL only, no hardware toolchains) ──────────────────────
# Pin to v1.13.3 — last release with full Gazebo Classic support on Ubuntu 20.04.
# Newer PX4 (main) requires Gazebo Harmonic which only runs on Ubuntu 22.04+.
#
# Two patches are applied before building:
#   1. px4_daemon server.cpp: retry poll() on EINTR (v1.13 server exits on any
#      signal, leaving rcS hung at `px4-param select` with no tty attached).
#   2. px4-rc.simulator: replaced with a no-op since we run Gazebo outside PX4
#      via ROS; without this patch PX4 blocks forever on `simulator start -c 4560`
#      waiting for a lockstep connection that never comes.
RUN cd /root && git clone --branch v1.13.3 --recurse-submodules \
    https://github.com/PX4/PX4-Autopilot.git \
    && cd PX4-Autopilot && bash ./Tools/setup/ubuntu.sh --no-nuttx --no-sim-tools \
    && sed -i 's|PX4_ERR("poll() failed: %s", strerror(errno));|if (errno == EINTR) continue; PX4_ERR("poll() failed: %s", strerror(errno));|' \
        platforms/posix/src/px4/common/px4_daemon/server.cpp \
    && printf '#!/bin/sh\necho "[init] simulator module skipped (external Gazebo via ROS)"\n' \
        > ROMFS/px4fmu_common/init.d-posix/px4-rc.simulator \
    && DONT_RUN=1 make px4_sitl_default \
    && DONT_RUN=1 make px4_sitl none_rover

# ── Catkin workspace ────────────────────────────────────────────────────────
RUN mkdir -p /root/catkin_ws/src

# rpg_vikit (camera models dependency)
RUN cd /root/catkin_ws/src \
    && git clone https://github.com/xuankuzcr/rpg_vikit.git

# FAST-LIVO2 (upstream ROS1 version)
RUN cd /root/catkin_ws/src \
    && git clone https://github.com/hku-mars/FAST-LIVO2.git

# ── Copy simulation files into the cloned repo ──────────────────────────────
COPY config/gazebo_px4_rover.yaml   /root/catkin_ws/src/FAST-LIVO2/config/
COPY config/camera_gazebo.yaml      /root/catkin_ws/src/FAST-LIVO2/config/
COPY launch/gazebo_px4_rover.launch /root/catkin_ws/src/FAST-LIVO2/launch/
COPY simulation/models/             /root/catkin_ws/src/FAST-LIVO2/simulation/models/
COPY simulation/worlds/             /root/catkin_ws/src/FAST-LIVO2/simulation/worlds/

# ── Build ───────────────────────────────────────────────────────────────────
ENV CMAKE_MODULE_PATH=/usr/local/share/cmake/Modules
RUN source /opt/ros/noetic/setup.bash \
    && cd /root/catkin_ws \
    && catkin_make -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_MODULE_PATH=/usr/local/share/cmake/Modules \
        -j$(nproc)

# ── Environment setup ──────────────────────────────────────────────────────
RUN echo 'source /opt/ros/noetic/setup.bash' >> /root/.bashrc \
    && echo 'source /root/catkin_ws/devel/setup.bash' >> /root/.bashrc \
    && echo 'export GAZEBO_MODEL_PATH=/root/catkin_ws/src/FAST-LIVO2/simulation/models:${GAZEBO_MODEL_PATH}' >> /root/.bashrc

# ── Entrypoint ──────────────────────────────────────────────────────────────
COPY simulation/docker/entrypoint.sh /root/entrypoint.sh
RUN chmod +x /root/entrypoint.sh

ENTRYPOINT ["/root/entrypoint.sh"]
CMD ["bash"]
