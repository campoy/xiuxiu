import Foundation

/// Whisper language code ("en", "es", "ca", ...) or "auto" to detect it from the first 30s.
let language = "auto"

/// Whisper continues this text -- its punctuation and casing, but also its *language*. A prompt
/// in one language rewrites audio in another into that language, so this covers every language
/// likely to turn up in an entry rather than just Spanish and English. With a Spanish/English-only
/// prompt, French audio came back as broken Spanish even though detection had correctly said "fr".
let initialPrompt = "Hoy fue un día largo, pero bueno. I finally finished the project, and honestly, it felt great. Aujourd'hui, j'ai bien travaillé, franchement. Avui ha estat un bon dia, la veritat."

let modelFileName = "ggml-large-v3-turbo-q5_0.bin"
let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(modelFileName)")!
