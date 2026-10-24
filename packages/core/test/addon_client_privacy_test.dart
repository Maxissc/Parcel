import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

void main() {
  test('una falla de red no copia la URL con tokens al mensaje', () async {
    const url = 'https://addon.example/token-secreto-123/manifest.json';
    final client = AddonClient(
      MockClient((request) async {
        throw http.ClientException('Connection refused', request.url);
      }),
    );

    final error = await client
        .fetchManifest(url)
        .then<AddonException?>((_) => null)
        .catchError((Object e) => e as AddonException);

    expect(error, isNotNull);
    expect(error!.reason, AddonFailureReason.network);
    expect(error.message, isNot(contains('token-secreto-123')));
    expect(error.toString(), isNot(contains('token-secreto-123')));
  });
}
