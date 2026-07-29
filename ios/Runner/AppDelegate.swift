import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let financeCaptureContextChannelName =
    "com.mobilefinanceassistant/finance_capture_context"
  private let unstableTimezoneKeys: Set<String> = ["Factory", "localtime", "posixrules"]
  private var financeCaptureContextChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: financeCaptureContextChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(
          FlutterError(
            code: "CAPTURE_CONTEXT_UNAVAILABLE",
            message: "Finance capture context is unavailable.",
            details: nil
          )
        )
        return
      }
      self.handleFinanceCaptureContext(call: call, result: result)
    }
    financeCaptureContextChannel = channel
  }

  private func handleFinanceCaptureContext(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard call.method == "capture" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      arguments.count == 1,
      let canonicalTimezone = arguments["canonicalTimezone"] as? String,
      let canonicalZone = stableIanaTimezone(canonicalTimezone)
    else {
      result(captureContextUnavailable())
      return
    }

    let capturedAt = Date()
    let osTimezone = TimeZone.autoupdatingCurrent.identifier
    guard let osZone = stableIanaTimezone(osTimezone) else {
      result(captureContextUnavailable())
      return
    }

    var osCalendar = Calendar(identifier: .gregorian)
    osCalendar.timeZone = osZone
    var canonicalCalendar = Calendar(identifier: .gregorian)
    canonicalCalendar.timeZone = canonicalZone

    guard
      let osLocalDate = localDate(capturedAt, calendar: osCalendar),
      let canonicalLocalDate = localDate(capturedAt, calendar: canonicalCalendar)
    else {
      result(captureContextUnavailable())
      return
    }

    let instantFormatter = ISO8601DateFormatter()
    instantFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    instantFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    result([
      "capturedAtUtc": instantFormatter.string(from: capturedAt),
      "osTimezone": osTimezone,
      "osLocalDate": osLocalDate,
      "canonicalTimezone": canonicalTimezone,
      "canonicalLocalDate": canonicalLocalDate,
    ])
  }

  private func stableIanaTimezone(_ value: String) -> TimeZone? {
    guard
      !value.isEmpty,
      value.count <= 128,
      value == value.trimmingCharacters(in: .whitespacesAndNewlines),
      !unstableTimezoneKeys.contains(value),
      value.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7f }),
      TimeZone.knownTimeZoneIdentifiers.contains(value),
      let timezone = TimeZone(identifier: value),
      timezone.identifier == value
    else {
      return nil
    }
    return timezone
  }

  private func localDate(_ instant: Date, calendar: Calendar) -> String? {
    let components = calendar.dateComponents([.year, .month, .day], from: instant)
    guard
      let year = components.year,
      let month = components.month,
      let day = components.day,
      (1900...2100).contains(year)
    else {
      return nil
    }
    return String(format: "%04d-%02d-%02d", year, month, day)
  }

  private func captureContextUnavailable() -> FlutterError {
    FlutterError(
      code: "CAPTURE_CONTEXT_UNAVAILABLE",
      message: "Finance capture context is unavailable.",
      details: nil
    )
  }
}
