#include "include/biometric_cipher/repositories/winrt_encrypt_repository_impl.h"
#include "include/biometric_cipher/errors/error_codes.h"
#include "include/biometric_cipher/enums/tpm_status.h"

#include <windows.h>
#include <winrt/windows.security.credentials.ui.h>

using namespace winrt;
using namespace winrt::impl;
using namespace Windows::Foundation;
using namespace Windows::Security::Cryptography;
using namespace Windows::Security::Cryptography::Core;
using namespace Windows::Security::Credentials;
using namespace Windows::Storage::Streams;
using namespace Windows::Security::Credentials::UI;

namespace biometric_cipher
{
	CryptographicKey WinrtEncryptRepositoryImpl::CreateAESKey(const IBuffer signature) const
	{
		auto sha256Provider = HashAlgorithmProvider::OpenAlgorithm(HashAlgorithmNames::Sha256());
		auto sha256Hash = sha256Provider.HashData(signature);
		if (sha256Hash.Length() != 32) {
			throw hresult_error(error_fail, L"Hash length is not 32 bytes.");
		}

		auto aesProvider = SymmetricKeyAlgorithmProvider::OpenAlgorithm(SymmetricAlgorithmNames::AesGcm());
		auto aesKey = aesProvider.CreateSymmetricKey(sha256Hash);

		return aesKey;
	}

	winrt::hstring WinrtEncryptRepositoryImpl::Encrypt(const CryptographicKey key, const winrt::hstring data) const
	{
		auto nonce = CryptographicBuffer::GenerateRandom(NONCE_LENGTH);

		auto dataToEncrypt = CryptographicBuffer::ConvertStringToBinary(data, BinaryStringEncoding::Utf16LE);
		auto encryptedAndAuthData = CryptographicEngine::EncryptAndAuthenticate(key, dataToEncrypt, nonce, nullptr);

		auto encryptedData = encryptedAndAuthData.EncryptedData();
		auto authTag = encryptedAndAuthData.AuthenticationTag();

		DataWriter writer;
		writer.WriteBuffer(nonce);
		writer.WriteBuffer(encryptedData);
		writer.WriteBuffer(authTag);
		auto combineBuffer = writer.DetachBuffer();

		auto encryptedBase64String = CryptographicBuffer::EncodeToBase64String(combineBuffer);

		return encryptedBase64String;
	}

	winrt::hstring WinrtEncryptRepositoryImpl::Decrypt(const CryptographicKey key, const winrt::hstring data) const
	{
		auto combineBuffer = CryptographicBuffer::DecodeFromBase64String(data);

		if (combineBuffer.Length() < NONCE_LENGTH + TAG_LENGTH) {
			throw hresult_error(error_decrypt, L"Encrypted data is too short or corrupted.");
		}

		auto reader = DataReader::FromBuffer(combineBuffer);
		auto nonce = reader.ReadBuffer(NONCE_LENGTH);
		auto encryptedData = reader.ReadBuffer(combineBuffer.Length() - NONCE_LENGTH - TAG_LENGTH);
		auto authTag = reader.ReadBuffer(TAG_LENGTH);

		auto decryptedData = CryptographicEngine::DecryptAndAuthenticate(key, encryptedData, nonce, authTag, nullptr);
		auto decryptedDataString = CryptographicBuffer::ConvertBinaryToString(BinaryStringEncoding::Utf16LE, decryptedData);

		return decryptedDataString;
	}
}
