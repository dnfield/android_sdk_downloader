import 'dart:io';

import 'package:archive/archive_io.dart';
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

Future<void> downloadAndExtractArchive(
  List<AndroidRepositoryRemotePackage> packages,
  OptionsRevision revision,
  String repositoryBase,
  Directory outDirectory, {
  String rootOverride,
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
  print('Downloading $displayName to ${outDirectory.path}....');

  Uri uri = Uri.parse(archive.url);
  if (!uri.isAbsolute) {
    uri = Uri.parse(repositoryBase + archive.url);
  }

  Archive platformZipArchive;
  Future<void> _handlePlatformZip(HttpClientResponse response) async {
    final InputStream input =
        InputStream(await response.expand((List<int> part) => part).toList());
    platformZipArchive = ZipDecoder().decodeBuffer(input);
  }

  await httpGet(uri, _handlePlatformZip);

  print('$displayName downloaded, extracting....');

  for (ArchiveFile file in platformZipArchive) {
    String filename = file.name;
    final int firstSlash = filename.indexOf(path.separator);
    if (firstSlash > 0 && rootOverride != null) {
      filename = path.join(
        outDirectory.path,
        rootOverride,
        filename.substring(firstSlash + 1),
      );
    } else {
      filename = path.join(outDirectory.path, filename);
    }
    if (file.isFile) {
      final File outFile = await File(filename).create(recursive: true);
      await outFile.writeAsBytes(file.content);
      await _setPermissions(outFile, file.unixPermissions);
    } else {
      await Directory(filename).create(recursive: true);
    }
  }
  print('$displayName complete.');
}

Future<void> _setPermissions(File outFile, int unixPermissions) async {
  if (Platform.isWindows) {
    return;
  }
  final ProcessResult result = await Process.run(
    'chmod',
    <String>[unixPermissions.toRadixString(8), outFile.absolute.path],
  );
  if (result.exitCode != 0) {
    throw FileSystemException('Failed to set permissions for $outFile');
  }
}
