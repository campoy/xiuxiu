import Foundation

/// Whisper language code ("en", "es", "ca", ...) or "auto" to detect it from the first 30s.
let language = "auto"

/// Whisper continues the style of this text: punctuation, casing, and the Spanish/English mix.
let initialPrompt = "Hoy fue un día largo, pero bueno. I finally finished the project, and honestly, it felt great. Mañana quiero descansar un poco."

let modelFileName = "ggml-large-v3-turbo-q5_0.bin"
let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(modelFileName)")!
