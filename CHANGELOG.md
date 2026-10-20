## 0.1.1

* Support `firebase_ai` 5.x and `firebase_core` 5.x alongside 4.x.

## 0.1.0

* Initial release.
* `FakeFirebaseAI`: an `http.Client` fake for `firebase_ai` backed by a reply queue or a `handler`.
* Supports `generateContent`, `generateContentStream`, `countTokens`, `ChatSession` and automatic function calling.
* Reply helpers for text, streamed chunks, function calls, blocked prompts and server errors.
* Records every request in `requests`.
