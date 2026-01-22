// ignore_for_file: avoid_print

import 'dart:io';

import 'package:args/args.dart';
import 'package:yaml/yaml.dart';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('pubspec', help: 'Path to pubspec.yaml file', defaultsTo: 'pubspec.yaml')
    ..addOption('build-number', help: 'Build number override');

  final args = parser.parse(arguments);
  final pubspecPath = args['pubspec'] as String;
  final pubspecFile = File(pubspecPath);
  if (!pubspecFile.existsSync()) {
    stderr.writeln('pubspec.yaml not found at path: $pubspecPath');
    exit(1);
  }

  final pubspecContent = pubspecFile.readAsStringSync();
  final pubspec = loadYaml(pubspecContent);

  // Getting version from pubspec.yaml
  final versionString = pubspec['version'] as String?;
  if (versionString == null) {
    stderr.writeln('Version not found in pubspec.yaml');
    exit(1);
  }

  // Parsing version and removing additional suffixes like beta.1
  final versionRegex = RegExp(r'^(\d+\.\d+\.\d+)(?:[+-].*)?$');
  final match = versionRegex.firstMatch(versionString);
  if (match == null) {
    stderr.writeln('Invalid version format in pubspec.yaml');
    exit(1);
  }

  // Main version (without beta.1 suffixes, etc.)
  final version = match.group(1);

  // Getting version number from version
  final buildNumberRegex = RegExp(r'(\d+)$');
  final buildNumberMatch = buildNumberRegex.firstMatch(match.group(0)!);
  if (buildNumberMatch == null) {
    stderr.writeln('Failed to extract version number');
    exit(1);
  }
  final buildNumberPubspec = buildNumberMatch.group(1);

  // Getting build number from environment, --build-number argument, or pubspec.yaml
  final buildNumber =
      args['build-number'] ?? Platform.environment['GITHUB_RUN_NUMBER'] ?? buildNumberPubspec?.toString();

  if (buildNumber == null) {
    stderr.writeln('Build number not found in arguments, environment, or pubspec.yaml');
    exit(1);
  }

  // Assembling the version for Windows (format: X.Y.Z.Build)
  final windowsVersion = '$version.$buildNumber';

  // Output the result to stdout
  print(windowsVersion);
}
