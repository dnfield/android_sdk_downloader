// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;

import 'src/android_repository.dart';
import 'src/http.dart';
import 'src/options.dart';

const String _androidRepositoryXml =
    'https://dl.google.com/android/repository/repository2-1.xml';

const List<String> _allowedPlatforms = <String>[
  '28',
  '22',
];

Future<void> main(List<String> args) async {
  final ArgParser argParser = ArgParser()
    ..addOption(
      'repository-xml',
      abbr: 'r',
      help: 'Specifies the location of the Android Repository XML file.',
      defaultsTo: _androidRepositoryXml,
    )
    ..addOption(
      'platform',
      abbr: 'p',
      help: 'Specifies the Android platform version, e.g. 28',
      allowed: _allowedPlatforms,
      defaultsTo: '28',
    )
    ..addOption(
      'platform-revision',
      help: 'Specifies the Android platform revision, e.g. 6 for 28_r06',
      defaultsTo: '6',
    )
    ..addOption(
      'out',
      abbr: 'o',
      help: 'The directory to write downloaded files to.',
      defaultsTo: '.',
    )
    ..addOption(
      'os',
      help: 'The OS type to download for.  Defaults to current platform.',
      defaultsTo: Platform.operatingSystem,
      allowed: osTypeMap.keys,
    )
    ..addOption(
      'build-tools-version',
      help: 'The build-tools version to download.  Must be in format of '
          '<major>.<minor>.<micro>, e.g. 28.0.3; '
          'or <major>.<minor>.<micro>.<rc/preview>, e.g. 28.0.0.2',
      defaultsTo: '28.0.3',
    )
    ..addOption(
      'platform-tools-version',
      help: 'The platform-tools version to download.  Must be in format of '
          '<major>.<minor>.<micro>, e.g. 28.0.1; '
          'or <major>.<minor>.<micro>.<rc/preview>, e.g. 28.0.0.2',
      defaultsTo: '28.0.1',
    )
    ..addOption(
      'tools-version',
      help: 'The tools version to download.  Must be in format of '
          '<major>.<minor>.<micro>, e.g. 26.1.1; '
          'or <major>.<minor>.<micro>.<rc/preview>, e.g. 28.1.1.2',
      defaultsTo: '26.1.1',
    )
    ..addOption(
      'ndk-version',
      help: 'The ndk version to download.  Must be in format of '
          '<major>.<minor>.<micro>, e.g. 28.0.3; '
          'or <major>.<minor>.<micro>.<rc/preview>, e.g. 28.0.0.2',
      defaultsTo: '18.1.5063045',
    )
    ..addFlag('accept-licenses',
        abbr: 'y',
        defaultsTo: false,
        help: 'Automatically accept Android SDK licenses.');

  final bool help = args.contains('-h') ||
      args.contains('--help') ||
      (args.isNotEmpty && args.first == 'help');
  if (help) {
    print(argParser.usage);
    return;
  }

  final Options options = Options.parseAndValidate(args, argParser);

  final AndroidRepository androidRepository =
      await _getAndroidRepository(options.repositoryXmlUri);
  assert(androidRepository.platforms.isNotEmpty);
  assert(androidRepository.buildTools.isNotEmpty);

  if (!options.acceptLicenses) {
    for (final AndroidRepositoryLicense license in androidRepository.licenses) {
      print(
          '================================================================================\n\n');
      print(license.text);
      stdout.write('Do you accept? (Y/n): ');
      final String result = stdin.readLineSync().trim().toLowerCase();
      if (result != '' && result.startsWith('y') == false) {
        print('Ending.');
        exit(-1);
      }
    }
  }

  final Directory sdkDir =
      await _mkdir(path.join(options.outDirectory.path, 'sdk'));
  final Directory platformDir =
      await _mkdir(path.join(sdkDir.path, 'platforms'));
  final Directory buildToolsDir =
      await _mkdir(path.join(sdkDir.path, 'build-tools'));

  final Directory ndkDir =
      await _mkdir(path.join(options.outDirectory.path, 'ndk'));

  final List<Future<void>> futures = <Future<void>>[
    downloadAndExtractArchive(
      androidRepository.platforms,
      OptionsRevision(null, options.platformRevision),
      options.repositoryBase,
      platformDir,
      rootOverride: 'android-${options.platformApiLevel}',
    ),
    downloadAndExtractArchive(
      androidRepository.buildTools,
      options.buildToolsRevision,
      options.repositoryBase,
      buildToolsDir,
      rootOverride: options.buildToolsRevision.raw,
      osType: options.osType,
    ),
    downloadAndExtractArchive(
      androidRepository.platformTools,
      options.platformToolsRevision,
      options.repositoryBase,
      sdkDir,
      osType: options.osType,
    ),
    downloadAndExtractArchive(
      androidRepository.tools,
      options.toolsRevision,
      options.repositoryBase,
      sdkDir,
      osType: options.osType,
    ),
    downloadAndExtractArchive(
      androidRepository.ndkBundles,
      options.ndkRevision,
      options.repositoryBase,
      ndkDir,
      rootOverride: '',
      osType: options.osType,
    ),
  ];
  await Future.wait<void>(futures);
  print('Done.');
}

Future<Directory> _mkdir(String dir) async {
  final Directory directory = Directory(dir);
  return await directory.create(recursive: true);
}

Future<AndroidRepository> _getAndroidRepository(Uri repositoryXmlUri) async {
  final StringBuffer repoXmlBuffer = StringBuffer();
  Future<void> _repositoryXmlHandler(HttpClientResponse response) async {
    await response.transform(utf8.decoder).forEach(repoXmlBuffer.write);
  }

  await httpGet(repositoryXmlUri, _repositoryXmlHandler);

  return parseAndroidRepositoryXml(repoXmlBuffer.toString());
}