// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

import 'android_repository.dart';
import 'options.dart';

typedef HttpResponseHandler = Future<void> Function(HttpClientResponse);

Future<void> httpGet(
  Uri url,
  HttpResponseHandler handler,
) async {
  assert(url != null);
  assert(handler != null);

  final HttpClient httpClient = HttpClient();

  try {
    final HttpClientRequest request = await httpClient.getUrl(url);
    final HttpClientResponse response = await request.close();
    await handler(response);
  } finally {
    httpClient.close();
  }
}

class DownloadTracker {
  DownloadTracker(this.name, this.total) : received = 0;

  final String name;
  final int total;
  int received;

  String get percent =>
      '${((received / total) * 100).round().toString().padLeft(3)}%';

  @override
  String toString() => '$name: $received/$total ($percent).';
}

final Map<String, DownloadTracker> _downloadTrackers =
    <String, DownloadTracker>{};
void _printDownloadTrackers() {
  for (final DownloadTracker tracker in _downloadTrackers.values) {
    stdout.write('${tracker.name}: ${tracker.percent} ');
  }

  if (_downloadTrackers.values
      .every((DownloadTracker tracker) => tracker.received == tracker.total)) {
    stdout.writeln();
    print('Downloads complete.');
  } else {
    stdout.write('\r');
  }
}

Future<String> downloadArchive(
  List<AndroidRepositoryRemotePackage> packages,
  OptionsRevision revision,
  String repositoryBase,
  Directory outDirectory, {
  OSType osType,
  int apiLevel,
}) async {
  AndroidRepositoryRemotePackage package;
  for (final AndroidRepositoryRemotePackage p in packages) {
    if (apiLevel != null && p is AndroidRepositoryPlatform) {
      if (p.apiLevel != apiLevel) {
        continue;
      }
    }
    if (p.revision.matches(
        revision.major, revision.minor, revision.micro, revision.preview)) {
      package = p;
      break;
    }
  }
  if (package == null) {
    throw StateError('Could not find package matching arguments: '
        '$revision, $osType, $apiLevel');
  }

  final String displayName = package.displayName;
  final AndroidRepositoryArchive archive = osType == null
      ? package.archives.first
      : package.archives.firstWhere(
          (AndroidRepositoryArchive archive) => archive.hostOS == osType,
        );

  Uri uri = Uri.parse(archive.url);
  if (!uri.isAbsolute) {
    uri = Uri.parse(repositoryBase + archive.url);
  }

  _downloadTrackers[displayName] = DownloadTracker(displayName, archive.size);
  final String outFileName = path.join(outDirectory.path, archive.url);
  final IOSink tempFileSink = File(outFileName).openWrite();

  Future<void> _handlePlatformZip(HttpClientResponse response) async {
    await for (List<int> data in response) {
      _downloadTrackers[displayName].received += data.length;
      tempFileSink.add(data);
      _printDownloadTrackers();
    }
    await tempFileSink.close();
  }

  await httpGet(uri, _handlePlatformZip);
  return outFileName;
}
