#include <gtest/gtest.h>

// Include the code under test
#include "include/biometric_cipher/common/debug_log.h"

namespace biometric_cipher {
	namespace test {

		using namespace biometric_cipher;

		class DebugLogTest : public ::testing::Test {};

		//
		// SliceMiddle must never crash on an empty input - a substr() out-of-range
		// exception inside the encrypt/decrypt flow would break the operation.
		//
		TEST(DebugLogTest, SliceMiddle_EmptyInput_ReturnsPlaceholder)
		{
			EXPECT_EQ(SliceMiddle(""), "<empty>");
		}

		//
		// A hex string shorter than 32 chars has no "middle slice" - the full
		// string must be returned (guards against negative-offset substr).
		//
		TEST(DebugLogTest, SliceMiddle_ShortInput_ReturnsFullString)
		{
			EXPECT_EQ(SliceMiddle("0123456789"), "0123456789");
			EXPECT_EQ(SliceMiddle(std::string(32, 'a')), std::string(32, 'a'));
		}

		//
		// A 64-hex-char string (32-byte SHA-256) must yield chars [16, 48),
		// i.e. bytes 8-23 of the hash. Catches off-by-one in the slice offset.
		//
		TEST(DebugLogTest, SliceMiddle_Exact64Chars_ReturnsChars16to47)
		{
			std::string hex(16, 'a');
			hex.append(32, 'b');
			hex.append(16, 'c');
			EXPECT_EQ(SliceMiddle(hex), std::string(32, 'b'));
		}

		//
		// A long signature hex (512 chars) must yield exactly 32 chars centered
		// at offset (512 - 32) / 2 = 240. Catches slice-length bugs.
		//
		TEST(DebugLogTest, SliceMiddle_LongInput_ReturnsMiddle32)
		{
			std::string hex(240, 'x');
			hex.append(32, 'y');
			hex.append(240, 'z');
			EXPECT_EQ(SliceMiddle(hex), std::string(32, 'y'));
		}

	}  // namespace test
}  // namespace biometric_cipher
