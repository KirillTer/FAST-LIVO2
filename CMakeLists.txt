cmake_minimum_required(VERSION 3.8)
project(fast_livo)

set(CMAKE_BUILD_TYPE "Release")
message(STATUS "Build Type: ${CMAKE_BUILD_TYPE}")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Set common compile options
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -pthread -fexceptions")

# Specific settings for Debug build
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -O0 -g")

# Detect CPU architecture
message(STATUS "Current CPU architecture: ${CMAKE_SYSTEM_PROCESSOR}")

# Specific settings for Release build
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(arm|aarch64|ARM|AARCH64)")
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
    set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -mcpu=native -mtune=native -ffast-math")
    message(STATUS "Using 64-bit ARM optimizations: -O3 -mcpu=native -mtune=native -ffast-math")
  else()
    set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -mcpu=native -mtune=native -mfpu=neon -ffast-math")
    message(STATUS "Using 32-bit ARM optimizations: -O3 -mcpu=native -mtune=native -mfpu=neon -ffast-math")
  endif()
  add_definitions(-DARM_ARCH)
elseif(APPLE AND CMAKE_SYSTEM_PROCESSOR MATCHES "arm64")
  set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -ffast-math")
  message(STATUS "Using Apple Silicon optimizations: -O3 -ffast-math")
  add_definitions(-DARM_ARCH)
else()
  set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -march=native -mtune=native -funroll-loops")
  message(STATUS "Using general x86 optimizations: -O3 -march=native -mtune=native -funroll-loops")
  add_definitions(-DX86_ARCH)
endif()

# Define project root directory
add_definitions(-DROOT_DIR=\"${CMAKE_CURRENT_SOURCE_DIR}/\")

# Detect CPU core count for potential multithreading optimization
include(ProcessorCount)
ProcessorCount(N)
message(STATUS "Processor count: ${N}")

if(N GREATER 4)
  math(EXPR PROC_NUM "4")
  add_definitions(-DMP_EN -DMP_PROC_NUM=${PROC_NUM})
  message(STATUS "Multithreading enabled. Cores: ${PROC_NUM}")
elseif(N GREATER 1)
  math(EXPR PROC_NUM "${N}")
  add_definitions(-DMP_EN -DMP_PROC_NUM=${PROC_NUM})
  message(STATUS "Multithreading enabled. Cores: ${PROC_NUM}")
else()
  add_definitions(-DMP_PROC_NUM=1)
  message(STATUS "Single core detected. Multithreading disabled.")
endif()

# Check for OpenMP support
find_package(OpenMP QUIET)
if(OpenMP_CXX_FOUND)
  message(STATUS "OpenMP found")
  add_compile_options(${OpenMP_CXX_FLAGS})
else()
  message(STATUS "OpenMP not found, proceeding without it")
endif()

# Check for mimalloc support
find_package(mimalloc QUIET)
if(mimalloc_FOUND)
  message(STATUS "mimalloc found")
else()
  message(STATUS "mimalloc not found, proceeding without it")
endif()

# Find ament and ROS2 dependencies
find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(std_msgs REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(geometry_msgs REQUIRED)
find_package(nav_msgs REQUIRED)
find_package(visualization_msgs REQUIRED)
find_package(tf2_ros REQUIRED)
find_package(tf2_geometry_msgs REQUIRED)
find_package(pcl_conversions REQUIRED)
find_package(cv_bridge REQUIRED)
find_package(image_transport REQUIRED)

find_package(Eigen3 REQUIRED)
find_package(PCL REQUIRED)
find_package(OpenCV REQUIRED)
find_package(Sophus REQUIRED)
find_package(Boost REQUIRED COMPONENTS thread)

# Include directories
include_directories(
  ${EIGEN3_INCLUDE_DIR}
  ${PCL_INCLUDE_DIRS}
  ${OpenCV_INCLUDE_DIRS}
  ${Sophus_INCLUDE_DIRS}
  include
  third_party/vikit/include
)

# Vikit third-party library (inlined, no ROS dependency)
add_library(vikit_common
  third_party/vikit/src/pinhole_camera.cpp
  third_party/vikit/src/math_utils.cpp
  third_party/vikit/src/vision.cpp
  third_party/vikit/src/robust_cost.cpp
  third_party/vikit/src/performance_monitor.cpp
)
target_include_directories(vikit_common PUBLIC
  third_party/vikit/include
)
ament_target_dependencies(vikit_common
  rclcpp
)
target_link_libraries(vikit_common
  ${OpenCV_LIBRARIES}
  ${Boost_LIBRARIES}
)

# Application libraries
add_library(vio src/vio.cpp src/frame.cpp src/visual_point.cpp)
add_library(lio src/voxel_map.cpp)
add_library(pre src/preprocess.cpp)
add_library(imu_proc src/IMU_Processing.cpp)
add_library(laser_mapping src/LIVMapper.cpp)

set(ROS2_DEPS
  rclcpp
  std_msgs
  sensor_msgs
  geometry_msgs
  nav_msgs
  visualization_msgs
  tf2_ros
  tf2_geometry_msgs
  pcl_conversions
  cv_bridge
  image_transport
)

foreach(lib vio lio pre imu_proc laser_mapping)
  ament_target_dependencies(${lib} ${ROS2_DEPS})
  target_link_libraries(${lib}
    vikit_common
    ${PCL_LIBRARIES}
    ${OpenCV_LIBRARIES}
    Sophus::Sophus
    ${Boost_LIBRARIES}
  )
endforeach()

# Main executable
add_executable(fastlivo_mapping src/main.cpp)
ament_target_dependencies(fastlivo_mapping ${ROS2_DEPS})
target_link_libraries(fastlivo_mapping
  laser_mapping
  vio
  lio
  pre
  imu_proc
  vikit_common
  ${PCL_LIBRARIES}
  ${OpenCV_LIBRARIES}
  Sophus::Sophus
  ${Boost_LIBRARIES}
)

if(mimalloc_FOUND)
  target_link_libraries(fastlivo_mapping mimalloc)
endif()

# Install
install(TARGETS fastlivo_mapping
  DESTINATION lib/${PROJECT_NAME}
)

install(DIRECTORY config launch
  DESTINATION share/${PROJECT_NAME}
)

ament_package()
