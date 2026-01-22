import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:locker/utils/list_extensions.dart';

// TODO(m.semenov): analyze this class and refactor if needed

/// A utility class for analyzing process memory to detect sensitive data leaks.
/// This is intended for debug/testing purposes only and should not be used in production.
class MemoryAnalyzer {
  /// Returns the process ID of the current process
  static int get currentPid => pid;

  /// Reads memory map of the current process
  /// Returns list of memory regions as (start_address, size) tuples
  static Future<List<(int, int)>> _getMemoryMap() async {
    final regions = <(int, int)>[];

    if (Platform.isLinux || Platform.isAndroid) {
      // Read /proc/self/maps on Linux/Android
      final maps = File('/proc/self/maps').readAsLinesSync();
      for (final line in maps) {
        final parts = line.split(' ');
        final addresses = parts[0].split('-');
        final start = int.parse(addresses[0], radix: 16);
        final end = int.parse(addresses[1], radix: 16);
        regions.add((start, end - start));
      }
    } else if (Platform.isMacOS) {
      // Check if vmmap is available
      try {
        await Process.run('which', ['vmmap']);
      } catch (e) {
        throw Exception(
          'vmmap utility not found. Please install Xcode Command Line Tools.',
        );
      }

      // Use vmmap on macOS
      final result = await Process.run('vmmap', ['$pid']);
      final output = result.stdout as String;
      final lines = output.split('\n');

      // Parse vmmap output
      // Example line: "__TEXT                 0000000100000000-0000000100003000 [   12K] r-x/r-x SM=COW"
      final regionRegex = RegExp(r'\s+(\w+)\s+(\w+)-(\w+)');

      for (final line in lines) {
        final match = regionRegex.firstMatch(line);
        if (match != null) {
          final start = int.parse(match.group(2)!, radix: 16);
          final end = int.parse(match.group(3)!, radix: 16);

          // Skip regions that are not readable
          if (!line.contains('r-x') && !line.contains('rw-')) continue;

          regions.add((start, end - start));
        }
      }
    }
    // TODO(m.semenov): Add Windows support using VirtualQueryEx

    return regions;
  }

  /// Searches for a byte pattern in process memory
  /// Returns list of addresses where pattern was found
  static Future<Uint8List> findPattern(Uint8List pattern) async {
    final matches = <int>[];

    try {
      final regions = await _getMemoryMap();

      // For each memory region
      for (final (start, size) in regions) {
        try {
          // Create pointer to memory region
          final ptr = ffi.Pointer<ffi.Uint8>.fromAddress(start);

          // Read memory region into Uint8List
          final buffer = ptr.asTypedList(size);

          // Search for pattern
          for (var i = 0; i <= buffer.length - pattern.length; i++) {
            var found = true;
            for (var j = 0; j < pattern.length; j++) {
              if (buffer[i + j] != pattern[j]) {
                found = false;
                break;
              }
            }
            if (found) {
              matches.add(start + i);
            }
          }
        } catch (e) {
          // Ignore errors reading inaccessible memory regions
          continue;
        }
      }
    } catch (e, st) {
      logger.logError('Error scanning memory: $e', stackTrace: st);
    }

    return matches.toUint8List();
  }

  /// Helper method to search for string patterns
  static Future<Uint8List> findString(String pattern) => findPattern(pattern.codeUnits.toUint8List());

  /// Helper method to search for hex patterns
  static Future<Uint8List> findHexPattern(String hexPattern) async {
    // Convert hex string to bytes
    final bytes = <int>[];
    for (var i = 0; i < hexPattern.length; i += 2) {
      bytes.add(int.parse(hexPattern.substring(i, i + 2), radix: 16));
    }
    return findPattern(bytes.toUint8List());
  }
}

/// Example usage:
/// ```dart
/// // Search for a string
/// final stringMatches = await MemoryAnalyzer.findString('sensitive_password');
///
/// // Search for specific bytes
/// final byteMatches = await MemoryAnalyzer.findPattern([0xDE, 0xAD, 0xBE, 0xEF]);
///
/// // Search for hex pattern
/// final hexMatches = await MemoryAnalyzer.findHexPattern('DEADBEEF');
/// ```
