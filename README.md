# fake_firebase_ai

A fake for [`firebase_ai`](https://pub.dev/packages/firebase_ai) (Firebase AI Logic) for unit and widget tests. No network, no API key, same answers every run.

`FakeFirebaseAI` swaps out the HTTP layer, not the SDK. You get a **real** `GenerativeModel`, so the SDK's own code still runs in your tests: streaming, `ChatSession` history, automatic function calling and error mapping all behave as they do in production.

## Install

```yaml
dev_dependencies:
  fake_firebase_ai: ^0.1.0
```

## Usage

```dart
import 'package:fake_firebase_ai/fake_firebase_ai.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replies', () async {
    final ai = FakeFirebaseAI()..reply('Hello!');
    final model = await ai.generativeModel('gemini-2.5-flash');

    final response = await model.generateContent([Content.text('Hi')]);

    expect(response.text, 'Hello!');
    expect(ai.requests.single.text, 'Hi');
  });
}
```

`generativeModel()` mocks `firebase_core` for you. You don't need `Firebase.initializeApp` or any platform channel setup.

### Replies

Replies are queued and used in order, one per `generateContent` / `generateContentStream` call.

```dart
ai.reply('text');                                   // a plain reply
ai.replyStream(['Hel', 'lo']);                      // one SSE chunk each
ai.replyFunctionCall('getWeather', {'city': 'Seoul'});
ai.replyBlocked();                                  // promptFeedback.blockReason = SAFETY
ai.replyError(429, 'Quota exceeded');               // throws QuotaExceeded
ai.replyError(400, 'Bad request');                  // throws ServerException
ai.enqueue(FakeResponse.raw([{...}]));              // any raw JSON response
```

Use a `handler` for dynamic replies. It runs when the queue is empty:

```dart
ai.handler = (request) => FakeResponse.text('echo: ${request.text}');
```

With an empty queue and no handler, the call throws a `StateError` that names the request.

### Function calling

`AutoFunctionDeclaration` runs inside the real `ChatSession`, so queue the call and then the final answer:

```dart
final model = await ai.generativeModel('gemini-2.5-flash', tools: [
  Tool.functionDeclarations([getWeather]),
]);
ai
  ..replyFunctionCall('getWeather', {'city': 'Seoul'})
  ..reply('It is sunny in Seoul.');

final response = await model.startChat().sendMessage(Content.text('Weather?'));
```

### Inspecting requests

Every request is recorded in `ai.requests` as a `FakeRequest`:

| Field | |
|---|---|
| `model` | `gemini-2.5-flash` |
| `method` | `generateContent`, `streamGenerateContent` or `countTokens` |
| `text` | every text part in the request, joined |
| `contents` | the prompt and chat history as raw JSON |
| `body` | the full request body as raw JSON |

### countTokens

`countTokens` counts whitespace-separated words by default. Set `ai.tokenCount = 42` to return a fixed value. It doesn't use the reply queue.

### Agent Platform (Vertex AI) or a custom setup

`FakeFirebaseAI` is an `http.Client`. Pass it to any model you build yourself. Call `generativeModel()` once first, or set up the Firebase mocks yourself:

```dart
FirebaseAI.agentPlatform().generativeModel(model: 'gemini-2.5-flash', httpClient: ai);
```

## Not supported yet

Live API (WebSocket), Imagen and `TemplateGenerativeModel`. Please open an issue if you need one of these.
