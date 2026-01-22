#include <gtest/gtest.h>

// C++/WinRT headers
#include <winrt/windows.storage.streams.h>
#include <winrt/windows.security.cryptography.h>
#include <winrt/windows.security.cryptography.core.h>

// Include the code under test
#include "include/secure_mnemonic/repositories/winrt_encrypt_repository_impl.h"

namespace secure_mnemonic {
	namespace test {

		using namespace secure_mnemonic;
        using namespace winrt;
        using namespace winrt::Windows::Security::Cryptography;
        using namespace winrt::Windows::Security::Cryptography::Core;
        using namespace winrt::Windows::Storage::Streams;

		class WinrtEncryptRepositoryTest : public ::testing::Test {
		protected:
			WinrtEncryptRepositoryImpl m_Repository;
		};

        //
        // 1. Basic test: CreateAESKey with an arbitrary signature
        //    The method internally hashes the signature with SHA256,
        //    which should always be 32 bytes. We just verify no exception is thrown
        //    and that we get a valid CryptographicKey back.
        //
        TEST_F(WinrtEncryptRepositoryTest, CreateAESKey_SucceedsWithValidSignature)
        {
            // Arrange
            // Let's create a 10-byte random buffer (though any size is fine).
            auto randomSignature = CryptographicBuffer::GenerateRandom(10);

            // Act
            auto key = m_Repository.CreateAESKey(randomSignature);

            // Assert
            // If it doesn't throw, we consider this a pass. 
            // We might also verify that 'key' is not null, but CryptographicKey is a value object.
            SUCCEED();
        }

        //
        // 2. Round-trip test: Encrypt and then Decrypt the same data. 
        //    If everything is correct, the decrypted string should match original.
        //
        TEST_F(WinrtEncryptRepositoryTest, EncryptDecrypt_RoundTrip)
        {
            // Arrange: create a random signature => create the AES key
            auto randomSignature = CryptographicBuffer::GenerateRandom(10);
            auto key = m_Repository.CreateAESKey(randomSignature);

            // Some sample text
            winrt::hstring original = L"Hello, World! This is a test.";

            // Act: encrypt and then decrypt
            auto ciphertext = m_Repository.Encrypt(key, original);
            auto roundTripResult = m_Repository.Decrypt(key, ciphertext);

            // Assert
            EXPECT_EQ(roundTripResult, original);
        }

        //
        // 3. Test that if the ciphertext is corrupted, Decrypt throws.
        //    We'll flip some bits in the encrypted buffer and expect an error.
        //
        TEST_F(WinrtEncryptRepositoryTest, Decrypt_ThrowsIfCiphertextCorrupted)
        {
            // Arrange
            auto randomSignature = CryptographicBuffer::GenerateRandom(10);
            auto key = m_Repository.CreateAESKey(randomSignature);

            winrt::hstring original = L"Corruption test data";
            auto validCiphertext = m_Repository.Encrypt(key, original);

            // Convert from base64 back to a buffer
            auto buffer = CryptographicBuffer::DecodeFromBase64String(validCiphertext);

            // Copy to a winrt::com_array to tamper
            winrt::com_array<uint8_t> data{};
            CryptographicBuffer::CopyToByteArray(buffer, data);

            // Flip the first byte if there's at least one
            if (!data.empty())
            {
                data[0] = static_cast<uint8_t>(~data[0]);
            }

            // Re-encode the tampered buffer
            IBuffer tamperedBuffer = CryptographicBuffer::CreateFromByteArray(data);
            auto tamperedCiphertext = CryptographicBuffer::EncodeToBase64String(tamperedBuffer);

            // Act & Assert: we expect an exception (e.g., hresult_error)
            EXPECT_THROW(
                m_Repository.Decrypt(key, tamperedCiphertext),
                winrt::hresult_error
            );
        }

        // Test 4: Verify non-deterministic encryption.
        // Encrypting the same plaintext twice should produce different ciphertexts,
        // and decrypting each returns the original plaintext.
        TEST_F(WinrtEncryptRepositoryTest, Encrypt_NonDeterministicEncryption) {
            // Arrange
            auto randomSignature = CryptographicBuffer::GenerateRandom(10);
            auto key = m_Repository.CreateAESKey(randomSignature);
            hstring original = L"Test non-deterministic encryption";

            // Act: Encrypt the same plaintext twice.
            auto ciphertext1 = m_Repository.Encrypt(key, original);
            auto ciphertext2 = m_Repository.Encrypt(key, original);

            // Assert: Check that both ciphertexts are non-empty.
            EXPECT_FALSE(ciphertext1.empty()) << "Ciphertext1 should not be empty";
            EXPECT_FALSE(ciphertext2.empty()) << "Ciphertext2 should not be empty";

            // Verify that the ciphertexts differ, confirming non-deterministic encryption.
            EXPECT_NE(ciphertext1, ciphertext2) << "Ciphertexts should differ on repeated encryption calls";

            // Decrypt each ciphertext.
            auto decrypted1 = m_Repository.Decrypt(key, ciphertext1);
            auto decrypted2 = m_Repository.Decrypt(key, ciphertext2);

            // Verify that decrypted texts match the original plaintext.
            EXPECT_EQ(decrypted1, original);
            EXPECT_EQ(decrypted2, original);
        }
	}
}
