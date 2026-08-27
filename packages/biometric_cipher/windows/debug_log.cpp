#include "include/biometric_cipher/common/debug_log.h"

#ifdef BIO_CIPHER_DEBUG
#include <windows.h>

#include <cstdio>
#include <fstream>
#include <iostream>
#include <winrt/windows.security.cryptography.h>

using namespace winrt;
using namespace Windows::Security::Cryptography;
using namespace Windows::Storage::Streams;
#endif

namespace biometric_cipher
{
	std::string SliceMiddle(const std::string& hex)
	{
		if (hex.empty()) {
			return "<empty>";
		}

		if (hex.length() <= 32) {
			return hex;
		}

		return hex.substr((hex.length() - 32) / 2, 32);
	}

#ifdef BIO_CIPHER_DEBUG
	namespace
	{
		std::string Timestamp()
		{
			SYSTEMTIME st;
			GetLocalTime(&st);

			char buf[16];
			std::snprintf(buf, sizeof(buf), "%02d:%02d:%02d.%03d",
				st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
			return buf;
		}

		void WriteLine(const std::string& line)
		{
			std::cout << line << std::endl;
			OutputDebugStringA((line + "\n").c_str());

			char tempPath[MAX_PATH];
			if (GetTempPathA(MAX_PATH, tempPath) == 0) {
				return;
			}

			// Debug logging must never break the encrypt/decrypt flow, so any
			// file-write failure is silently ignored.
			try {
				std::ofstream file(std::string(tempPath) + "biometric_cipher_debug.log", std::ios::app);
				if (file) {
					file << line << "\n";
				}
			}
			catch (...) {
			}
		}

		std::string HexSlice(const IBuffer buffer)
		{
			if (!buffer) {
				return "<null>";
			}

			return SliceMiddle(to_string(CryptographicBuffer::EncodeToHexString(buffer)));
		}
	}

	void LogSignature(const char* operation, const std::string& tag, const IBuffer signature)
	{
		WriteLine("[bio-debug] " + Timestamp() + " op=" + operation + " tag=" + tag + " sig=" + HexSlice(signature));
	}

	void LogKeyHash(const IBuffer sha256Hash)
	{
		WriteLine("[bio-debug] " + Timestamp() + " key=" + HexSlice(sha256Hash));
	}
#endif
}
