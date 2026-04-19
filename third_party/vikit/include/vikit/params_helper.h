#ifndef VIKIT_PARAMS_HELPER_H_
#define VIKIT_PARAMS_HELPER_H_

#include <string>
#include <rclcpp/rclcpp.hpp>

namespace vk {

// ROS2-compatible parameter helpers.
// These require a global node pointer to be set before use.
inline rclcpp::Node::SharedPtr& global_node() {
  static rclcpp::Node::SharedPtr node = nullptr;
  return node;
}

inline void setNode(rclcpp::Node::SharedPtr node) {
  global_node() = node;
}

inline bool hasParam(const std::string& name) {
  return global_node()->has_parameter(name);
}

template<typename T>
T getParam(const std::string& name, const T& defaultValue) {
  // ROS2 parameter names use '.' not '/'
  std::string ros2_name = name;
  for (auto& c : ros2_name) { if (c == '/') c = '.'; }

  if (!global_node()->has_parameter(ros2_name)) {
    global_node()->declare_parameter<T>(ros2_name, defaultValue);
  }
  T v;
  if (global_node()->get_parameter(ros2_name, v)) {
    RCLCPP_INFO_STREAM(global_node()->get_logger(), "Found parameter: " << ros2_name << ", value: " << v);
    return v;
  }
  RCLCPP_WARN_STREAM(global_node()->get_logger(), "Cannot find value for parameter: " << ros2_name << ", assigning default: " << defaultValue);
  return defaultValue;
}

template<typename T>
T getParam(const std::string& name) {
  std::string ros2_name = name;
  for (auto& c : ros2_name) { if (c == '/') c = '.'; }

  if (!global_node()->has_parameter(ros2_name)) {
    global_node()->declare_parameter<T>(ros2_name, T());
  }
  T v;
  if (global_node()->get_parameter(ros2_name, v)) {
    RCLCPP_INFO_STREAM(global_node()->get_logger(), "Found parameter: " << ros2_name << ", value: " << v);
    return v;
  }
  RCLCPP_ERROR_STREAM(global_node()->get_logger(), "Cannot find value for parameter: " << ros2_name);
  return T();
}

} // namespace vk

#endif // VIKIT_PARAMS_HELPER_H_
