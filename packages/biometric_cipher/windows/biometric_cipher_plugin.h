#ifndef FLUTTER_PLUGIN_BIOMETRIC_CIPHER_PLUGIN_H_
#define FLUTTER_PLUGIN_BIOMETRIC_CIPHER_PLUGIN_H_

#include "include/biometric_cipher/common/argument_parser.h"
#include "include/biometric_cipher/services/biometric_cipher_service.h"
#include "include/biometric_cipher/storages/config_storage.h"


#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <windows.h>
#include <memory>
#include <string>
#include <winrt/base.h>
#include <winrt/windows.foundation.h>
#include <winrt/windows.system.threading.h>

namespace biometric_cipher {

class BiometricCipherPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  BiometricCipherPlugin();

  virtual ~BiometricCipherPlugin();

  // Disallow copy and assign.
  BiometricCipherPlugin(const BiometricCipherPlugin&) = delete;
  BiometricCipherPlugin& operator=(const BiometricCipherPlugin&) = delete;

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

	biometric_cipher::ArgumentParser m_Argument_parser;
	std::shared_ptr<biometric_cipher::ConfigStorage> m_ConfigStorage;
	std::shared_ptr<biometric_cipher::BiometricCipherService> m_SecureService;
};

}  // namespace biometric_cipher

#endif  // FLUTTER_PLUGIN_BIOMETRIC_CIPHER_PLUGIN_H_
