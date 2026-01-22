#ifndef FLUTTER_PLUGIN_SECURE_MNEMONIC_PLUGIN_H_
#define FLUTTER_PLUGIN_SECURE_MNEMONIC_PLUGIN_H_

#include "include/secure_mnemonic/common/argument_parser.h"
#include "include/secure_mnemonic/services/secure_mnemonic_service.h"
#include "include/secure_mnemonic/storages/config_storage.h"


#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <windows.h>
#include <memory>
#include <string>
#include <winrt/base.h>
#include <winrt/windows.foundation.h>
#include <winrt/windows.system.threading.h>

namespace secure_mnemonic {

class SecureMnemonicPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  SecureMnemonicPlugin();

  virtual ~SecureMnemonicPlugin();

  // Disallow copy and assign.
  SecureMnemonicPlugin(const SecureMnemonicPlugin&) = delete;
  SecureMnemonicPlugin& operator=(const SecureMnemonicPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

private:
	winrt::fire_and_forget GetTPMStatus(
		std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

	winrt::fire_and_forget GetBiometryStatus(
		std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

	winrt::fire_and_forget GenerateKeyCoroutine(
		const std::string& tag,
		std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

	winrt::fire_and_forget DeleteKeyCoroutine(
		const std::string& tag,
		std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

	winrt::fire_and_forget EncryptCoroutine(
		const std::string& tag,
		const std::string& data,
		std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

	winrt::fire_and_forget DecryptCoroutine(
		const std::string& tag,
		const std::string& data,
		std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

	void OutputException(winrt::hresult hr, std::string& errorMessage);

	secure_mnemonic::ArgumentParser m_Argument_parser;
	std::shared_ptr<secure_mnemonic::ConfigStorage> m_ConfigStorage;
	std::shared_ptr<secure_mnemonic::SecureMnemonicService> m_SecureService;
};

}  // namespace secure_mnemonic

#endif  // FLUTTER_PLUGIN_SECURE_MNEMONIC_PLUGIN_H_
