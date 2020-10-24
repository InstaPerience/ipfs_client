import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:quiver/core.dart';
import 'streams/streamable.dart';
import 'streams/streamable.dart';

class HashNode {
  final String hash;
  final String name;
  final BigInt size;
  static const List<String> _HASH_JSON_KEY = ['Hash', 'Key', 'Cid'];

  static BigInt _parseStringAsNumber(dynamic size) {
    if (size is String) {
      return BigInt.parse(size.toString());
    } else if (size is int) {
      return BigInt.from(size);
    } else {
      return BigInt.from(-1);
    }
  }

  HashNode(this.hash, [this.name = '', this.size]);

  factory HashNode.fromJson(Map<String, dynamic> json) {
    var maybeHash = _HASH_JSON_KEY.map((var key) => json[key])
            .map((var value) => Optional.fromNullable(value))
            .firstWhere((var maybeValue) => maybeValue.isPresent, orElse : () => Optional.absent());

    maybeHash.ifAbsent(() => throw Exception('Hash cannot be null...'));
    var name = Optional.fromNullable(json['Name']).transform((var s) => s.toString()).or('');
    var size = Optional.fromNullable(json['Size']).transform((var s) => _parseStringAsNumber(s)).or(BigInt.from(-1));
    return HashNode(maybeHash.value, name, size);
  }

  @override
  String toString() {
    return 'HashNode{hash: $hash, name: $name, size: $size}';
  }
}

class IpfsHttpRequest extends http.BaseRequest {

  static const String _allowed = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _LINE_FEED = "\r\n";

  final List<Streamable> _streamableEntities;
  final String _boundary = _createBoundary();

  IpfsHttpRequest(this._streamableEntities, Uri url) : super('POST', url);

  @override
  http.ByteStream finalize() {
    headers['content-type'] = 'multipart/form-data; boundary=${_boundary}';
    super.finalize();
    return http.ByteStream(_finalize());
  }

  static const String EMPTY = '';

  Stream<List<int>> _finalize() async* {
    for (var entity in _streamableEntities) {
      if (entity.isDirectory()) {
        yield* _addDirectoryRecursively(EMPTY, entity);
      } else {
        yield* _addFile('file', EMPTY, entity);
      }
    }
    yield utf8.encode('--' + _boundary + '--' + _LINE_FEED);
  }

  Stream<List<int>> _addDirectoryRecursively(
          String parentPath, Streamable streamable) async* {
    var path = p.join(parentPath, streamable.getName().value);
    yield* _addDirectory(path);
    for (var child in streamable.getChildren()) {
      if (child.isDirectory()) {
        yield* _addDirectoryRecursively(path, child);
      } else {
        yield* _addFile('file', path, child);
      }
    }
  }

  Stream<List<int>> _addDirectory(String path) async* {
    var buffer = StringBuffer();
    buffer.write('--');
    buffer.write(_boundary);
    buffer.write(_LINE_FEED);
    buffer.write('Content-Disposition: file; filename="${Uri.encodeComponent(path)}"');
    buffer.write(_LINE_FEED);
    buffer.write('Content-Type: application/x-directory');
    buffer.write(_LINE_FEED);
    buffer.write('Content-Transfer-Encoding: binary');
    buffer.write(_LINE_FEED);
    buffer.write(_LINE_FEED);
    buffer.write(_LINE_FEED);
    yield utf8.encode(buffer.toString());
  }

  Stream<List<int>> _addFile(
          String fieldName, String parent, Streamable uploadFile) async* {
    var buffer = StringBuffer();
    buffer.write('--');
    buffer.write(_boundary);
    buffer.write(_LINE_FEED);
    var maybeEncodedFileName = uploadFile.getName()
            .transform((String name) => p.join(parent, name))
            .transform((String resolved) => Uri.encodeFull(resolved));

    if (maybeEncodedFileName.isPresent) {
      buffer.write(
              'Content-Disposition: file; filename="${maybeEncodedFileName.value}";');
    } else {
      buffer.write('Content-Disposition: file; name="${fieldName}";');
    }

    buffer.write(_LINE_FEED);
    buffer.write('Content-Type: application/octet-stream');
    buffer.write(_LINE_FEED);
    buffer.write('Content-Transfer-Encoding: binary');
    buffer.write(_LINE_FEED);
    buffer.write(_LINE_FEED);
    yield utf8.encode(buffer.toString());

    yield* uploadFile.getByteStream();
    yield utf8.encode(_LINE_FEED);
  }

  static String _createBoundary() {
    var r = Random();
    var buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(_allowed[r.nextInt(_allowed.length)]);
    }
    return buffer.toString();
  }
}

class IpfsClient {
  static const int DEFAULT_CONNECT_TIMEOUT_MILLIS = 10000;
  static const int DEFAULT_READ_TIMEOUT_MILLIS = 60000;
  static const String DEFAULT_ROOT_PATH = '/api/v0/';
  static const String LOCAL_HOST = '127.0.0.1';

  final Uri _uri;
  final int _connectTimeoutMillis;
  final int _readTimeoutMillis;
  final http.Client _httpClient = http.Client();

  IpfsClient(this._uri,
             {connectTimeoutMillis = DEFAULT_CONNECT_TIMEOUT_MILLIS,
               readTimeoutMillis = DEFAULT_READ_TIMEOUT_MILLIS})
          : _connectTimeoutMillis = connectTimeoutMillis,
            _readTimeoutMillis = readTimeoutMillis;

  factory IpfsClient.newClient(String host, int port, {int connectTimeoutMillis = DEFAULT_CONNECT_TIMEOUT_MILLIS, int readTimeoutMillis = DEFAULT_READ_TIMEOUT_MILLIS, bool ssl = false}) {
    var uri;
    if (ssl) {
      uri = Uri.https('${host}:${port}', DEFAULT_ROOT_PATH);
    } else {
      uri = Uri.http('${host}:${port}', DEFAULT_ROOT_PATH);
    }
    return IpfsClient(uri, connectTimeoutMillis: connectTimeoutMillis, readTimeoutMillis: readTimeoutMillis);
  }

  factory IpfsClient.local(
          {int port = 5001,
            int connectTimeoutMillis = DEFAULT_CONNECT_TIMEOUT_MILLIS,
            int readTimeoutMillis = DEFAULT_READ_TIMEOUT_MILLIS,
            bool ssl = false}) {
    var uri;
    if (ssl) {
      uri = Uri.https('${LOCAL_HOST}:${port}', DEFAULT_ROOT_PATH);
    } else {
      uri = Uri.http('${LOCAL_HOST}:${port}', DEFAULT_ROOT_PATH);
    }
    return IpfsClient(uri,
                              connectTimeoutMillis: connectTimeoutMillis,
                              readTimeoutMillis: readTimeoutMillis);
  }

  Future<List<HashNode>> add(Streamable streamable, {bool wrap = false, bool hashOnly = false}) {
    return addAll([streamable], wrap: wrap, hashOnly: hashOnly);
  }

  Future<HashNode> addFile(FileStream streamable, {bool wrap = false, bool hashOnly = false}) {
    return add(streamable, wrap : wrap, hashOnly: hashOnly).then((var list) => list[0]);
  }

  Future<HashNode> addContent(ByteArrayStream streamable, {bool wrap = false, bool hashOnly = false}) {
    return add(streamable, wrap : wrap, hashOnly: hashOnly).then((var list) => list[0]);
  }

  Future<String> cat(HashNode hashNode) async {
    return catAsBytes(hashNode).then((var bytes) => utf8.decode(bytes));
  }

  Future<Uint8List> catAsBytes(HashNode hashNode) async {
    var uri = _uri.resolve('cat').replace(queryParameters: {'arg' : hashNode.hash});
    var response = _httpClient.post(uri, headers : {'Content-type' : 'application/json'});
    var value = await response;
    return value.bodyBytes;
  }

  Future<List<HashNode>> addAll(List<Streamable> elements, {bool wrap = false, bool hashOnly = false}) {
    var uri = _uri.resolve('add').replace(queryParameters: {
      'stream-channels': true.toString(),
      'wrap-with-directory': wrap.toString(),
      'only-hash': hashOnly.toString()
    });
    print('Making request: ${uri}');
    var request = IpfsHttpRequest(elements, uri);

    return _httpClient.send(request)
            .then((http.StreamedResponse resp) => resp.stream)
            .then((http.ByteStream stream) => stream.toBytes())
            .then((var bytes) => String.fromCharCodes(bytes))
            .then((var jsonString) => toHashNodes(jsonString))
            .timeout(Duration(milliseconds: _readTimeoutMillis));
  }

  List<HashNode> toHashNodes(String jsonResponse) {
    return jsonResponse.split('\n')
            .map((var s) => s.trim()).where((var s) => s.isNotEmpty)
            .map((var split) => jsonDecode(split))
            .map((var map) => HashNode.fromJson(map)).toList();
  }

  void close() {
    _httpClient.close();
  }
}