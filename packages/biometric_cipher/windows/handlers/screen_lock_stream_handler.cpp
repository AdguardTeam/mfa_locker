#include "include/biometric_cipher/handlers/screen_lock_stream_handler.h"

namespace biometric_cipher {

ScreenLockStreamHandler::ScreenLockStreamHandler(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}

ScreenLockStreamHandler::~ScreenLockStreamHandler() {
  UnregisterWindowProc();
}

std::unique_ptr<flutter::StreamHandler<flutter::EncodableValue>>
ScreenLockStreamHandler::CreateStreamHandler() {
  return std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      // onListen
      [this](const flutter::EncodableValue* arguments,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        event_sink_ = std::move(events);
        RegisterWindowProc();
        return nullptr;
      },
      // onCancel
      [this](const flutter::EncodableValue* arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        UnregisterWindowProc();
        event_sink_ = nullptr;
        return nullptr;
      });
}

void ScreenLockStreamHandler::RegisterWindowProc() {
  HWND hwnd = registrar_->GetView()->GetNativeWindow();
  WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION);

  window_proc_delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowMessage(hwnd, message, wparam, lparam);
      });
}

void ScreenLockStreamHandler::UnregisterWindowProc() {
  if (window_proc_delegate_id_ >= 0) {
    HWND hwnd = registrar_->GetView()->GetNativeWindow();
    WTSUnRegisterSessionNotification(hwnd);
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_delegate_id_);
    window_proc_delegate_id_ = -1;
  }
}

std::optional<LRESULT> ScreenLockStreamHandler::HandleWindowMessage(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_WTSSESSION_CHANGE && wparam == WTS_SESSION_LOCK) {
    if (event_sink_) {
      event_sink_->Success(flutter::EncodableValue(true));
    }
  }
  return std::nullopt;
}

}  // namespace biometric_cipher
