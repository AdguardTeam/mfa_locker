#pragma once

#include <string>
#include <winrt/base.h>
#include <winrt/windows.storage.streams.h>

namespace biometric_cipher {
	// Returns the middle 32 hex chars of a hex string, the full string when it is
	// shorter than 32 chars, and "<empty>" for an empty string. Always compiled
	// (pure function operating on caller-provided data) so it stays unit-testable
	// even when debug logging is disabled.
	std::string SliceMiddle(const std::string& hex);

#ifdef BIO_CIPHER_DEBUG
	void LogSignature(
		const char* operation,
		const std::string& tag,
		winrt::Windows::Storage::Streams::IBuffer signature);
	void LogKeyHash(winrt::Windows::Storage::Streams::IBuffer sha256Hash);
#else
	// No-ops compiled away entirely when BIO_CIPHER_DEBUG is not defined, keeping
	// call sites free of preprocessor guards.
	inline void LogSignature(
		const char*,
		const std::string&,
		winrt::Windows::Storage::Streams::IBuffer)
	{}
	inline void LogKeyHash(winrt::Windows::Storage::Streams::IBuffer) {}
#endif
}
