import AVFoundation
import Flutter
import UIKit

public final class OlympusVideoStickerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "olympus/video_sticker",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(OlympusVideoStickerPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "prepare" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String,
      let startNumber = arguments["startSeconds"] as? NSNumber,
      let durationNumber = arguments["durationSeconds"] as? NSNumber
    else {
      result(error("invalid_arguments", "Dados incompletos para preparar o video."))
      return
    }
    let startSeconds = startNumber.intValue
    let durationSeconds = durationNumber.intValue
    guard FileManager.default.fileExists(atPath: path) else {
      result(error("file_not_found", "O video selecionado nao foi localizado."))
      return
    }
    guard startSeconds >= 0, durationSeconds >= 1, durationSeconds <= 8 else {
      result(error("invalid_range", "O trecho precisa ter entre 1 e 8 segundos."))
      return
    }

    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    asset.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) { [weak self] in
      guard let self = self else { return }
      var tracksError: NSError?
      var durationError: NSError?
      guard
        asset.statusOfValue(forKey: "tracks", error: &tracksError) == .loaded,
        asset.statusOfValue(forKey: "duration", error: &durationError) == .loaded
      else {
        self.finish(
          result,
          value: self.error(
            "asset_load_failed",
            tracksError?.localizedDescription
              ?? durationError?.localizedDescription
              ?? "O iPhone nao conseguiu abrir o video."
          )
        )
        return
      }
      self.export(
        asset: asset,
        startSeconds: startSeconds,
        durationSeconds: durationSeconds,
        result: result
      )
    }
  }

  private func export(
    asset: AVAsset,
    startSeconds: Int,
    durationSeconds: Int,
    result: @escaping FlutterResult
  ) {
    guard let sourceTrack = asset.tracks(withMediaType: .video).first else {
      finish(result, value: error("no_video_track", "O arquivo nao possui uma faixa de video."))
      return
    }

    let totalSeconds = CMTimeGetSeconds(asset.duration)
    guard totalSeconds.isFinite, totalSeconds > 0, Double(startSeconds) < totalSeconds else {
      finish(result, value: error("invalid_duration", "O video nao possui duracao valida."))
      return
    }

    let actualDuration = min(Double(durationSeconds), totalSeconds - Double(startSeconds))
    guard actualDuration >= 0.5 else {
      finish(result, value: error("clip_too_short", "O trecho escolhido ficou curto demais."))
      return
    }

    let composition = AVMutableComposition()
    guard let compositionTrack = composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
      finish(result, value: error("composition_failed", "Nao foi possivel preparar o video."))
      return
    }

    let timescale = max(asset.duration.timescale, 600)
    let start = CMTime(seconds: Double(startSeconds), preferredTimescale: timescale)
    let duration = CMTime(seconds: actualDuration, preferredTimescale: timescale)
    do {
      try compositionTrack.insertTimeRange(
        CMTimeRange(start: start, duration: duration),
        of: sourceTrack,
        at: .zero
      )
      compositionTrack.preferredTransform = sourceTrack.preferredTransform
    } catch {
      finish(result, value: self.error("trim_failed", error.localizedDescription))
      return
    }

    let presets = AVAssetExportSession.exportPresets(compatibleWith: composition)
    let preset: String
    if presets.contains(AVAssetExportPreset640x480) {
      preset = AVAssetExportPreset640x480
    } else if presets.contains(AVAssetExportPresetMediumQuality) {
      preset = AVAssetExportPresetMediumQuality
    } else {
      preset = AVAssetExportPresetLowQuality
    }
    guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else {
      finish(result, value: error("exporter_failed", "O iPhone nao criou o exportador MP4."))
      return
    }
    guard exporter.supportedFileTypes.contains(.mp4) else {
      finish(result, value: error("mp4_not_supported", "Este video nao pode ser convertido para MP4."))
      return
    }

    let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("olympus_sticker_\(UUID().uuidString).mp4")
    try? FileManager.default.removeItem(at: outputURL)
    exporter.outputURL = outputURL
    exporter.outputFileType = .mp4
    exporter.shouldOptimizeForNetworkUse = true
    exporter.exportAsynchronously { [weak self] in
      guard let self = self else { return }
      guard exporter.status == .completed else {
        self.finish(
          result,
          value: self.error(
            "export_failed",
            exporter.error?.localizedDescription ?? "O iPhone nao concluiu a conversao do video."
          )
        )
        return
      }
      guard
        FileManager.default.fileExists(atPath: outputURL.path),
        let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
        let size = attributes[.size] as? NSNumber,
        size.int64Value > 0
      else {
        self.finish(
          result,
          value: self.error("empty_output", "O MP4 criado pelo iPhone esta vazio.")
        )
        return
      }
      self.finish(result, value: outputURL.path)
    }
  }

  private func finish(_ result: @escaping FlutterResult, value: Any?) {
    DispatchQueue.main.async { result(value) }
  }

  private func error(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }
}
