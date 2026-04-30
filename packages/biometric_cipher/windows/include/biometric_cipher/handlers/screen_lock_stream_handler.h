#pragma once

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <wtsapi32.h>

#include <optional>

namespace biometric_cipher {

class ScreenLockStreamHandler {
 public:
  explicit ScreenLockStreamHandler(flutter::PluginRegistrarWindows* registrar);
  ~ScreenLockStreamHandler();

  ScreenLockStreamHandler(const ScreenLockStreamHandler&) = delete;
  ScreenLockStreamHandler& operator=(const ScreenLockStreamHandler&) = delete;

  std::unique_ptr<flutter::StreamHandler<flutter::EncodableValue>> CreateStreamHandler();

 private:
  static constexpr int kInvalidDelegateId = -1;

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
  int window_proc_delegate_id_ = kInvalidDelegateId;
  HWND top_level_hwnd_ = nullptr;

  std::optional<LRESULT> HandleWindowMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  void RegisterWindowProc();
  void UnregisterWindowProc();
};

}  // namespace biometric_cipher
