import Foundation
import Shared
import IRelayLogging

// MARK: - Voice Engine

/// TTS and STT engine using AVFoundation on macOS/iOS.
public actor VoiceEngine {
    private let logger = Log.logger(for: "voice")

    public init() {}

    // MARK: - Text to Speech

    /// Speak text using system TTS (macOS: NSSpeechSynthesizer, iOS: AVSpeechSynthesizer).
    public func speak(_ text: String, voice: String? = nil) async throws {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        var args = [text]
        if let voice { args = ["-v", voice] + args }
        process.arguments = args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        logger.debug("TTS completed: \(text.prefix(50))...")
        #else
        throw IRelayError.platformUnsupported("Voice TTS requires macOS")
        #endif
    }

    /// Generate audio data from text (for sending as audio message).
    public func synthesize(_ text: String, voice: String? = nil) async throws -> Data {
        #if os(macOS)
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).aiff")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        var args = ["-o", tempFile.path, text]
        if let voice { args = ["-v", voice] + args }
        process.arguments = args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        defer { try? FileManager.default.removeItem(at: tempFile) }
        return try Data(contentsOf: tempFile)
        #else
        throw IRelayError.platformUnsupported("Voice synthesis requires macOS")
        #endif
    }

    // MARK: - Available Voices

    /// List available system voices.
    public func availableVoices() async throws -> [String] {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["--voice=?"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.components(separatedBy: "\n")
            .compactMap { line in
                let name = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first
                return name?.isEmpty == false ? name : nil
            }
        #else
        return []
        #endif
    }
}
