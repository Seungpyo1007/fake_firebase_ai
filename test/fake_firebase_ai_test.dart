import 'package:fake_firebase_ai/fake_firebase_ai.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseAI ai;
  late GenerativeModel model;

  setUp(() async {
    ai = FakeFirebaseAI();
    model = await ai.generativeModel('gemini-2.5-flash');
  });

  test('generateContent returns the queued text', () async {
    ai.reply('Hello!');
    final response = await model.generateContent([Content.text('Hi')]);
    expect(response.text, 'Hello!');
    expect(ai.requests.single.model, 'gemini-2.5-flash');
    expect(ai.requests.single.method, 'generateContent');
    expect(ai.requests.single.text, 'Hi');
  });

  test('generateContentStream yields chunks in order', () async {
    ai.replyStream(['Hel', 'lo', '!']);
    final chunks = await model
        .generateContentStream([Content.text('Hi')])
        .map((r) => r.text)
        .toList();
    expect(chunks, ['Hel', 'lo', '!']);
    expect(ai.requests.single.isStream, isTrue);
  });

  test('stream reply merges for a non-streamed call', () async {
    ai.replyStream(['Hel', 'lo']);
    final response = await model.generateContent([Content.text('Hi')]);
    expect(response.text, 'Hello');
  });

  test('chat sends the history on the next turn', () async {
    ai
      ..reply('Hi, Kim.')
      ..reply('Your name is Kim.');
    final chat = model.startChat();
    await chat.sendMessage(Content.text('I am Kim.'));
    final response = await chat.sendMessage(Content.text('Who am I?'));
    expect(response.text, 'Your name is Kim.');
    expect(ai.requests.last.contents, hasLength(3));
    expect(chat.history, hasLength(4));
  });

  test('chat runs auto function calls through the SDK', () async {
    String? calledWith;
    final weather = AutoFunctionDeclaration(
      name: 'getWeather',
      description: 'Weather for a city',
      parameters: {'city': Schema.string()},
      callable: (args) {
        calledWith = args['city'] as String?;
        return {'weather': 'sunny'};
      },
    );
    model = await ai.generativeModel(
      'gemini-2.5-flash',
      tools: [
        Tool.functionDeclarations([weather]),
      ],
    );
    ai
      ..replyFunctionCall('getWeather', {'city': 'Seoul'})
      ..reply('It is sunny in Seoul.');

    final response = await model.startChat().sendMessage(
      Content.text('Weather?'),
    );

    expect(calledWith, 'Seoul');
    expect(response.text, 'It is sunny in Seoul.');
    expect(ai.requests.last.body.toString(), contains('functionResponse'));
  });

  test('handler answers when the queue is empty', () async {
    ai.handler = (req) => FakeResponse.text('echo: ${req.text}');
    final response = await model.generateContent([Content.text('ping')]);
    expect(response.text, 'echo: ping');
  });

  test('quota errors map to QuotaExceeded', () async {
    ai.replyError(
      429,
      'Quota exceeded for requests.',
      status: 'RESOURCE_EXHAUSTED',
    );
    expect(
      model.generateContent([Content.text('Hi')]),
      throwsA(isA<QuotaExceeded>()),
    );
  });

  test('streamed errors map to exceptions too', () async {
    ai.replyError(400, 'Bad request');
    expect(
      model.generateContentStream([Content.text('Hi')]).toList(),
      throwsA(isA<ServerException>()),
    );
  });

  test('5xx errors throw FirebaseAIException', () async {
    ai.replyError(503, 'Unavailable');
    expect(
      model.generateContent([Content.text('Hi')]),
      throwsA(isA<FirebaseAIException>()),
    );
  });

  test('blocked prompts surface promptFeedback', () async {
    ai.replyBlocked();
    final response = await model.generateContent([Content.text('bad')]);
    expect(response.promptFeedback?.blockReason, BlockReason.safety);
    expect(response.candidates, isEmpty);
  });

  test('countTokens counts words unless tokenCount is set', () async {
    expect(
      (await model.countTokens([Content.text('one two three')])).totalTokens,
      3,
    );
    ai.tokenCount = 42;
    expect((await model.countTokens([Content.text('x')])).totalTokens, 42);
  });

  test('works as the httpClient of an agent platform model', () async {
    final vertex = FirebaseAI.agentPlatform().generativeModel(
      model: 'gemini-2.5-flash',
      httpClient: ai,
    );
    ai.reply('From the agent platform.');
    final response = await vertex.generateContent([Content.text('Hi')]);
    expect(response.text, 'From the agent platform.');
    expect(ai.requests.single.model, 'gemini-2.5-flash');
  });

  test('an empty queue throws a clear StateError', () async {
    expect(
      model.generateContent([Content.text('Hi')]),
      throwsA(isA<StateError>()),
    );
  });
}
