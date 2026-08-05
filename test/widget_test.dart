import 'package:flutter_test/flutter_test.dart';
import 'package:hallerschipper/main.dart';

void main() {
  test('song search matches number, title and text', () {
    const song = Song(
      number: '17',
      title: 'Die Windjammer kommen',
      category: 'Seemannslieder',
      text: 'Die Segel erscheinen am Horizont.',
    );

    expect(song.matches('17'), isTrue);
    expect(song.matches('windjammer'), isTrue);
    expect(song.matches('Horizont'), isTrue);
    expect(song.matches('Weihnachten'), isFalse);
  });
}
