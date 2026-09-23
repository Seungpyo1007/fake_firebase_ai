/// A fake for `package:firebase_ai`, for unit and widget tests.
///
/// [FakeFirebaseAI] is an `http.Client` that answers the Firebase AI Logic
/// REST calls in memory. The real `GenerativeModel` and `ChatSession` still
/// run, so streaming, chat history and automatic function calling behave as
/// they do in production.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// A request received by [FakeFirebaseAI].
class FakeRequest {
  FakeRequest._(this.uri, this.body);

  /// The full request URI.
  final Uri uri;

  /// The decoded JSON request body, as sent by the SDK.
  final Map<String, Object?> body;

  /// The model name, e.g. `gemini-2.5-flash`.
  String get model => uri.pathSegments.last.split(':').first;

  /// The API method: `generateContent`, `streamGenerateContent` or
  /// `countTokens`.
  String get method => uri.pathSegments.last.split(':').last;

  /// Whether the SDK asked for a streamed response.
  bool get isStream => method == 'streamGenerateContent';

  /// The `contents` sent with the request (the prompt and chat history).
  List<Map<String, Object?>> get contents => [
    for (final c in (body['contents'] as List? ?? const []))
      c as Map<String, Object?>,
  ];

  /// All text parts of the request, joined with newlines.
  String get text => _texts(body).join('\n');
}

/// A canned response returned by [FakeFirebaseAI].
class FakeResponse {
  /// A response with a raw HTTP [statusCode] and JSON [chunks].
  ///
  /// Streamed requests get one server-sent event per chunk. Non-streamed
  /// requests get the chunks merged into a single response.
  const FakeResponse.raw(this.chunks, {this.statusCode = 200});

  /// A model reply with [text].
  factory FakeResponse.text(String text) => FakeResponse.stream([text]);

  /// A model reply split into streamed [chunks] of text.
  factory FakeResponse.stream(List<String> chunks) => FakeResponse.raw([
    for (final (i, chunk) in chunks.indexed)
      _candidate([
        {'text': chunk},
      ], last: i == chunks.length - 1),
  ]);

  /// A model reply that calls the function [name] with [args].
  factory FakeResponse.functionCall(
    String name, [
    Map<String, Object?> args = const {},
  ]) => FakeResponse.raw([
    _candidate([
      {
        'functionCall': {'name': name, 'args': args},
      },
    ], last: true),
  ]);

  /// A reply whose prompt was blocked, e.g. with [reason] `SAFETY`.
  factory FakeResponse.blocked([String reason = 'SAFETY']) => FakeResponse.raw([
    {
      'promptFeedback': {'blockReason': reason, 'safetyRatings': []},
    },
  ]);

  /// A server error.
  ///
  /// A [message] containing "quota" makes the SDK throw `QuotaExceeded`,
  /// any other message `ServerException`. A [code] of 500 or more makes
  /// non-streamed calls throw a plain `FirebaseAIException`.
  factory FakeResponse.error(
    int code,
    String message, {
    String status = 'UNKNOWN',
  }) => FakeResponse.raw([
    {
      'error': {'code': code, 'message': message, 'status': status},
    },
  ], statusCode: code);

  /// The HTTP status code.
  final int statusCode;

  /// The JSON response bodies.
  final List<Map<String, Object?>> chunks;

  static Map<String, Object?> _candidate(
    List<Object?> parts, {
    required bool last,
  }) => {
    'candidates': [
      {
        'content': {'role': 'model', 'parts': parts},
        if (last) 'finishReason': 'STOP',
      },
    ],
  };

  Map<String, Object?> get _merged {
    if (chunks.length == 1) return chunks.single;
    final parts = [
      for (final c in chunks)
        for (final cand in (c['candidates'] as List? ?? const []).take(1))
          ...((cand as Map)['content'] as Map)['parts'] as List,
    ];
    return {...chunks.last, ..._candidate(parts, last: true)};
  }
}

/// A fake Firebase AI Logic backend.
///
/// Queue replies with [reply], [replyStream], [replyFunctionCall],
/// [replyBlocked], [replyError] or [enqueue], or answer dynamically with
/// [handler]. Every request is recorded in [requests].
class FakeFirebaseAI extends http.BaseClient {
  final _queue = Queue<FakeResponse>();

  /// Every request received, oldest first. `countTokens` calls included.
  final List<FakeRequest> requests = [];

  /// Answers requests when the queue is empty.
  FakeResponse Function(FakeRequest request)? handler;

  /// The `totalTokens` returned by `countTokens`.
  ///
  /// When null, the whitespace-separated words of the request are counted.
  int? tokenCount;

  /// Queues [response] for the next generate call.
  void enqueue(FakeResponse response) => _queue.add(response);

  /// Queues a reply with [text].
  void reply(String text) => enqueue(FakeResponse.text(text));

  /// Queues a reply streamed as [chunks].
  void replyStream(List<String> chunks) => enqueue(FakeResponse.stream(chunks));

  /// Queues a reply that calls the function [name] with [args].
  void replyFunctionCall(String name, [Map<String, Object?> args = const {}]) =>
      enqueue(FakeResponse.functionCall(name, args));

  /// Queues a reply whose prompt was blocked.
  void replyBlocked([String reason = 'SAFETY']) =>
      enqueue(FakeResponse.blocked(reason));

  /// Queues a server error. See [FakeResponse.error].
  void replyError(int code, String message, {String status = 'UNKNOWN'}) =>
      enqueue(FakeResponse.error(code, message, status: status));

  /// Clears the queue and the recorded requests.
  void reset() {
    _queue.clear();
    requests.clear();
  }

  /// Returns a real `GenerativeModel` wired to this fake.
  ///
  /// Mocks `firebase_core` and initializes a default app when needed, so no
  /// other test setup is required.
  Future<GenerativeModel> generativeModel(
    String model, {
    List<SafetySetting>? safetySettings,
    GenerationConfig? generationConfig,
    List<Tool>? tools,
    ToolConfig? toolConfig,
    Content? systemInstruction,
  }) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    final app = Firebase.apps.isEmpty
        ? await Firebase.initializeApp()
        : Firebase.app();
    return FirebaseAI.googleAI(app: app).generativeModel(
      model: model,
      safetySettings: safetySettings,
      generationConfig: generationConfig,
      tools: tools,
      toolConfig: toolConfig,
      systemInstruction: systemInstruction,
      httpClient: this,
    );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final fake = FakeRequest._(
      request.url,
      jsonDecode(utf8.decode(bytes)) as Map<String, Object?>,
    );
    requests.add(fake);

    if (fake.method == 'countTokens') {
      final total =
          tokenCount ??
          fake.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      return _respond(200, [
        jsonEncode({'totalTokens': total}),
      ]);
    }

    final FakeResponse response;
    if (_queue.isNotEmpty) {
      response = _queue.removeFirst();
    } else if (handler != null) {
      response = handler!(fake);
    } else {
      throw StateError(
        'FakeFirebaseAI got a ${fake.method} request for ${fake.model} '
        'but has no queued reply. Call reply() or set handler first.',
      );
    }

    if (!fake.isStream || response.statusCode != 200) {
      return _respond(response.statusCode, [jsonEncode(response._merged)]);
    }
    return _respond(200, [
      for (final chunk in response.chunks) 'data: ${jsonEncode(chunk)}\r\n\r\n',
    ]);
  }

  http.StreamedResponse _respond(int status, List<String> body) =>
      http.StreamedResponse(
        Stream.fromIterable(body.map(utf8.encode)),
        status,
        headers: {'content-type': 'application/json'},
      );
}

Iterable<String> _texts(Object? json) sync* {
  if (json is Map) {
    if (json['text'] case final String text) yield text;
    for (final v in json.values) {
      yield* _texts(v);
    }
  } else if (json is List) {
    for (final v in json) {
      yield* _texts(v);
    }
  }
}
