import 'package:fake_firebase_ai/fake_firebase_ai.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';

/// The code under test: takes a model, so tests can pass a fake one.
Future<String> summarize(GenerativeModel model, String article) async {
  final response = await model.generateContent([
    Content.text('Summarize in one line:\n$article'),
  ]);
  return response.text ?? '';
}

void main() {
  test('summarize sends the article and returns the reply', () async {
    final ai = FakeFirebaseAI()..reply('Cats are great.');
    final model = await ai.generativeModel('gemini-2.5-flash');

    expect(
      await summarize(model, 'A long article about cats.'),
      'Cats are great.',
    );
    expect(ai.requests.single.text, contains('about cats'));
  });
}
