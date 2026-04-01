#pragma once

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>
#include <wtsapi32.h>

namespace biometric_cipher {

class ScreenLockStreamHandler {
 public:
  explicit ScreenLockStreamHandler(flutter::PluginRegistrarWindows* registrar);
  ~ScreenLockStreamHandler();

  ScreenLockStreamHandler(const ScreenLockStreamHandler&) = delete;
  ScreenLockStreamHandler& operator=(const ScreenLockStreamHandler&) = delete;

  std::unique_ptr<flutter::StreamHandler<flutter::EncodableValue>> CreateStreamHandler();

 private:
  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
  int window_proc_delegate_id_ = -1;

  std::optional<LRESULT> HandleWindowMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  void RegisterWindowProc();
  void UnregisterWindowProc();
};

}  // namespace biometric_cipher
