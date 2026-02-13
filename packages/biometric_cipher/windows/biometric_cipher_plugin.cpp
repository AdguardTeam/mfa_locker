#include "biometric_cipher_plugin.h"
#include "include/biometric_cipher/enums/method_name.h"
#include "include/biometric_cipher/common/string_util.h"
#include "include/biometric_cipher/repositories/windows_tpm_repository_impl.h"
#include "include/biometric_cipher/repositories/windows_hello_repository_impl.h"
#include "include/biometric_cipher/repositories/winrt_encrypt_repository_impl.h"
#include "include/biometric_cipher/errors/error_codes.h"


// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include <winrt/windows.foundation.h>
#include <winrt/windows.system.threading.h>
#include <winrt/windows.foundation.collections.h>

using namespace winrt;
using namespace Windows::Foundation;
using namespace Windows::System::Threading;

using biometric_cipher::MethodName;
using biometric_cipher::ArgumentName;

namespace biometric_cipher {

// static
void BiometricCipherPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) 
{
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "biometric_cipher",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<BiometricCipherPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

BiometricCipherPlugin::BiometricCipherPlugin() : 
	m_ConfigStorage(std::make_shared<ConfigStorage>())
{
	auto windowsTpmRepository = std::make_shared<WindowsTpmRepositoryImpl>();
	auto windowsHelloRepository = std::make_shared<WindowsHelloRepositoryImpl>();
	auto winrtEncryptRepository = std::make_shared<WinrtEncryptRepositoryImpl>();
	m_SecureService = std::make_shared<BiometricCipherService>(
		m_ConfigStorage, 
		windowsHelloRepository, 
		windowsTpmRepository,
		winrtEncryptRepository
	);
}


BiometricCipherPlugin::~BiometricCipherPlugin() {}

void BiometricCipherPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &methodCall,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) 
{

	auto method = biometric_cipher::GetMethodName(methodCall.method_name());
    switch (method) {
	case MethodName::kGetTPMStatus:
	{
		GetTPMStatus(std::move(result));
		break;
	}

	case MethodName::kGetBiometryStatus:
	{
		GetBiometryStatus(std::move(result));
		break;
	}

	case MethodName::kGenerateKey:
	{
		auto arguments = m_Argument_parser.Parse(method, methodCall.arguments());
		const std::string tag = arguments[ArgumentName::kTag].stringArgument;

		GenerateKeyCoroutine(tag, std::move(result));
		break;
	}

    case MethodName::kEncrypt:
    {
		auto arguments = m_Argument_parser.Parse(method, methodCall.arguments());
		const std::string tag = arguments[ArgumentName::kTag].stringArgument;
		const std::string data = arguments[ArgumentName::kData].stringArgument;

		EncryptCoroutine(tag, data, std::move(result));
        break;
    }

	case MethodName::kDecrypt:
    {
		auto arguments = m_Argument_parser.Parse(method, methodCall.arguments());
		const std::string tag = arguments[ArgumentName::kTag].stringArgument;
		const std::string data = arguments[ArgumentName::kData].stringArgument;

		DecryptCoroutine(tag, data, std::move(result));
        break;

    }

	case MethodName::kDeleteKey:
    {
		auto arguments = m_Argument_parser.Parse(method, methodCall.arguments());
		const std::string tag = arguments[ArgumentName::kTag].stringArgument;

		DeleteKeyCoroutine(tag, std::move(result));
		break;
    }            

    case MethodName::kConfigure:
    {
		try {
			auto arguments = m_Argument_parser.Parse(method, methodCall.arguments());
			ConfigData configData(arguments[ArgumentName::kWindowsDataToSign].stringArgument);
			m_ConfigStorage->SetConfigData(configData);

            result->Success(NULL);
        }
		catch (const hresult_error& e) {
			auto hr = e.code();
			auto message = e.message();
			auto errorMessage = StringUtil::ConvertHStringToString(message);
			OutputException(hr, errorMessage);

			result->Error(GetErrorCodeString(hr), errorMessage);
		}
		break;
    }

	case MethodName::kNotImplemented:
	default:
		result->NotImplemented();
		break;
    }
}

winrt::fire_and_forget BiometricCipherPlugin::GetTPMStatus(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
	try {
		auto tpmStatus = co_await m_SecureService->GetTPMStatusAsync();

		result->Success(tpmStatus);
	}
	catch (const hresult_error& e) {
		auto hr = e.code();
		auto message = e.message();
		auto errorMessage = StringUtil::ConvertHStringToString(message);
		OutputException(hr, errorMessage);

		result->Error(GetErrorCodeString(hr), errorMessage);
	}
}

winrt::fire_and_forget BiometricCipherPlugin::GetBiometryStatus(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
	try {
		auto biometryStatus = co_await m_SecureService->GetBiometryStatusAsync();

		result->Success(biometryStatus);
	}
	catch (const hresult_error& e) {
		auto hr = e.code();
		auto message = e.message();
		auto errorMessage = StringUtil::ConvertHStringToString(message);
		OutputException(hr, errorMessage);

		result->Error(GetErrorCodeString(hr), errorMessage);
	}
}

winrt::fire_and_forget BiometricCipherPlugin::GenerateKeyCoroutine(
	const std::string& tag,
	std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) 
{
	try {
		co_await m_SecureService->GenerateKeyAsync(tag);

		result->Success(NULL);
	}
	catch (const hresult_error& e) {
		auto hr = e.code();
		auto message = e.message();
		auto errorMessage = StringUtil::ConvertHStringToString(message);
		OutputException(hr, errorMessage);

		result->Error(GetErrorCodeString(hr), errorMessage);
	}
}

winrt::fire_and_forget BiometricCipherPlugin::DeleteKeyCoroutine(
	const std::string& tag, 
	std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) 
{
	try {
		co_await m_SecureService->DeleteKeyAsync(tag);

		result->Success(NULL);
	}
	catch (const hresult_error& e) {
		auto hr = e.code();
		auto message = e.message();
		auto errorMessage = StringUtil::ConvertHStringToString(message);
		OutputException(hr, errorMessage);

		result->Error(GetErrorCodeString(hr), errorMessage);
	}
}

winrt::fire_and_forget BiometricCipherPlugin::EncryptCoroutine(
	const std::string& tag,
	const std::string& data,
	std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) 
{
	try {
		auto encryptedHString = co_await m_SecureService->EncryptAsync(tag, data);
		std::string encryptedString = StringUtil::ConvertHStringToString(encryptedHString);

		result->Success(encryptedString);
	}
	catch (const hresult_error& e) {
		auto hr = e.code();
		auto message = e.message();
		auto errorMessage = StringUtil::ConvertHStringToString(message);
		OutputException(hr, errorMessage);

		result->Error(GetErrorCodeString(hr), errorMessage);
	}
}

winrt::fire_and_forget BiometricCipherPlugin::DecryptCoroutine(
	const std::string& tag, 
	const std::string& data, 
	std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
	try {
		auto decryptedData = co_await m_SecureService->DecryptAsync(tag, data);
		std::string decryptedString = StringUtil::ConvertHStringToString(decryptedData);

		result->Success(decryptedString);
	}
	catch (const hresult_error& e) {
		auto hr = e.code();
		auto message = e.message();
		auto errorMessage = StringUtil::ConvertHStringToString(message);
		OutputException(hr, errorMessage);

		result->Error(GetErrorCodeString(hr), errorMessage);
	}
}

void BiometricCipherPlugin::OutputException(hresult hr, std::string& errorMessage)
{
	std::ostringstream ss;
	ss << "Error code: 0x" << std::hex << std::uppercase << hr.value;
	ss << " Message: " << errorMessage;
#ifdef DEBUG
	OutputDebugStringA(ss.str().c_str());
	OutputDebugStringA("\n");
#endif // DEBUG
}

}  // namespace biometric_cipher
