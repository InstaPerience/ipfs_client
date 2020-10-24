import 'package:ipfs_client/ipfs_client.dart';

Future<void> main() async {
    var client = IpfsClient.local();

    try {
        var byteStream = ByteArrayStream.fromString('Hello World !');
        var contentHash = await client.addContent(byteStream);
        var content = await client.cat(contentHash);
        print(content);
  } finally {
        client.close();
    }
}
