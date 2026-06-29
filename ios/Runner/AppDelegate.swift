import Flutter
import UIKit
import BackgroundTasks
import UserNotifications
import ActivityKit
import EventKit

private let backgroundRefreshIdentifier = "psyche.kelivo.background-generation.refresh"
private let backgroundProcessingIdentifier = "psyche.kelivo.background-generation.processing"

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let fileSaveHandler = NativeFileSaveHandler()
  private let backgroundGenerationHandler = IosBackgroundGenerationHandler()
  private let calendarHandler = IosCalendarHandler()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    backgroundGenerationHandler.registerBackgroundTasks()
    if let controller = window?.rootViewController as? FlutterViewController {
      let clipboardChannel = FlutterMethodChannel(name: "app.clipboard", binaryMessenger: controller.binaryMessenger)
      clipboardChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "getClipboardImages" {
          var paths: [String] = []
          if let image = UIPasteboard.general.image {
            if let data = image.pngData() ?? image.jpegData(compressionQuality: 0.95) {
              let tmp = NSTemporaryDirectory()
              let filename = "pasted_\(Int(Date().timeIntervalSince1970 * 1000)).png"
              let url = URL(fileURLWithPath: tmp).appendingPathComponent(filename)
              do {
                try data.write(to: url)
                paths.append(url.path)
              } catch {
                // ignore write error
              }
            }
          }
          result(paths)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }

      let fileSaveChannel = FlutterMethodChannel(name: "app.file_save", binaryMessenger: controller.binaryMessenger)
      fileSaveHandler.presentingViewController = controller
      fileSaveChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        guard call.method == "saveFileFromPath" else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.fileSaveHandler.handle(call: call, result: result)
      }

      let iosBackgroundChannel = FlutterMethodChannel(name: "app.ios_background_generation", binaryMessenger: controller.binaryMessenger)
      iosBackgroundChannel.setMethodCallHandler { [weak self] call, result in
        self?.backgroundGenerationHandler.handle(call: call, result: result)
      }

      let calendarChannel = FlutterMethodChannel(name: "app.calendar", binaryMessenger: controller.binaryMessenger)
      calendarChannel.setMethodCallHandler { [weak self] call, result in
        self?.calendarHandler.handle(call: call, result: result)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    backgroundGenerationHandler.dismissFinishedLiveActivityIfNeeded()
  }
}

// iPhone 联动：把 daddy 回话里的 [[cal]]/[[remind]] 暗号真写进系统日历 / 提醒事项（EventKit）。
private final class IosCalendarHandler {
  private let store = EKEventStore()

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getStatus":
      result([
        "calendar": IosCalendarHandler.isGranted(EKEventStore.authorizationStatus(for: .event)),
        "reminders": IosCalendarHandler.isGranted(EKEventStore.authorizationStatus(for: .reminder)),
      ])
    case "requestAccess":
      requestAccess(result: result)
    case "addEvent":
      addEvent(args: call.arguments as? [String: Any] ?? [:], result: result)
    case "addReminder":
      addReminder(args: call.arguments as? [String: Any] ?? [:], result: result)
    case "clearEventsByPrefix":
      clearEventsByPrefix(args: call.arguments as? [String: Any] ?? [:], result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func isGranted(_ status: EKAuthorizationStatus) -> Bool {
    if #available(iOS 17.0, *) {
      return status == .fullAccess
    }
    return status == .authorized
  }

  private func requestAccess(result: @escaping FlutterResult) {
    let group = DispatchGroup()
    var calOK = false
    var remOK = false

    group.enter()
    if #available(iOS 17.0, *) {
      store.requestFullAccessToEvents { granted, _ in calOK = granted; group.leave() }
    } else {
      store.requestAccess(to: .event) { granted, _ in calOK = granted; group.leave() }
    }

    group.enter()
    if #available(iOS 17.0, *) {
      store.requestFullAccessToReminders { granted, _ in remOK = granted; group.leave() }
    } else {
      store.requestAccess(to: .reminder) { granted, _ in remOK = granted; group.leave() }
    }

    group.notify(queue: .main) {
      result(["calendar": calOK, "reminders": remOK])
    }
  }

  // "YYYY-MM-DD" -> DateComponents(y/m/d); nil if malformed.
  private func dayComponents(_ dateStr: String) -> DateComponents? {
    let parts = dateStr.split(separator: "-")
    guard parts.count == 3,
          let y = Int(parts[0]), let mo = Int(parts[1]), let d = Int(parts[2]) else {
      return nil
    }
    var c = DateComponents()
    c.year = y
    c.month = mo
    c.day = d
    return c
  }

  // "HH:MM" -> (hour, minute); nil if malformed.
  private func hourMinute(_ timeStr: String) -> (Int, Int)? {
    let parts = timeStr.split(separator: ":")
    guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
    return (h, m)
  }

  private func addEvent(args: [String: Any], result: @escaping FlutterResult) {
    let title = (args["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let dateStr = (args["date"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let timeStr = (args["time"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let notes = (args["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, var comps = dayComponents(dateStr) else { result(false); return }

    let cal = Calendar.current
    let event = EKEvent(eventStore: store)
    event.title = title
    if let notes = notes, !notes.isEmpty { event.notes = notes }
    event.calendar = store.defaultCalendarForNewEvents

    if let timeStr = timeStr, !timeStr.isEmpty, let (h, m) = hourMinute(timeStr) {
      comps.hour = h
      comps.minute = m
      guard let start = cal.date(from: comps) else { result(false); return }
      event.startDate = start
      event.endDate = start.addingTimeInterval(3600)
      event.isAllDay = false
    } else {
      comps.hour = 0
      comps.minute = 0
      guard let start = cal.date(from: comps) else { result(false); return }
      event.startDate = start
      event.endDate = start
      event.isAllDay = true
    }

    do {
      try store.save(event, span: .thisEvent)
      result(true)
    } catch {
      result(false)
    }
  }

  // Deletes all events whose title starts with [prefix] within an optional date
  // window (defaults to 2024-01-01 .. now+1d). Used to clear the diary backfill
  // batch (titles prefixed "📔") before re-syncing them with notes. Returns the
  // number of events removed.
  private func clearEventsByPrefix(args: [String: Any], result: @escaping FlutterResult) {
    let prefix = (args["prefix"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prefix.isEmpty else { result(0); return }

    let cal = Calendar.current
    let start = (dayComponents(args["start"] as? String ?? "").flatMap { cal.date(from: $0) })
      ?? cal.date(from: DateComponents(year: 2024, month: 1, day: 1))!
    let end = Date().addingTimeInterval(86400)

    let calendars = store.calendars(for: .event)
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
    let events = store.events(matching: predicate)

    var removed = 0
    for ev in events where (ev.title ?? "").hasPrefix(prefix) {
      do {
        try store.remove(ev, span: .thisEvent)
        removed += 1
      } catch {
        // best-effort; keep going
      }
    }
    result(removed)
  }

  private func addReminder(args: [String: Any], result: @escaping FlutterResult) {
    let text = (args["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let dueStr = (args["due"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, let calendar = store.defaultCalendarForNewReminders() else {
      result(false)
      return
    }

    let reminder = EKReminder(eventStore: store)
    reminder.title = text
    reminder.calendar = calendar

    // due: "YYYY-MM-DD HH:MM"（HH:MM 可省）
    if let dueStr = dueStr, !dueStr.isEmpty {
      let segs = dueStr.split(separator: " ")
      if let datePart = segs.first, var comps = dayComponents(String(datePart)) {
        if segs.count > 1, let (h, m) = hourMinute(String(segs[1])) {
          comps.hour = h
          comps.minute = m
        }
        reminder.dueDateComponents = comps
      }
    }

    do {
      try store.save(reminder, commit: true)
      result(true)
    } catch {
      result(false)
    }
  }
}

private final class IosBackgroundGenerationHandler {
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var notificationsEnabled = false
  private var refreshEnabled = false
  private var liveActivity: Any?
  private var liveActivityRefreshTimer: Timer?
  private var liveActivityDisplayTitle = ""
  private var liveActivityDetail = ""
  private var liveActivityTokenCount = 0
  private var liveActivityTokenLabel = ""
  private var liveActivityStartedAt = Date()
  private var liveActivityFinishedAt: Date?
  private var liveActivityFinishedDetail = ""
  private var liveActivityFinished = false
  private var liveActivityWavePhase = 0

  func registerBackgroundTasks() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundRefreshIdentifier, using: nil) { task in
      self.handleBackgroundTask(task)
    }
    BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundProcessingIdentifier, using: nil) { task in
      self.handleBackgroundTask(task)
    }
  }

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getStatus":
      getStatus(result: result)
    case "requestNotificationAuthorization":
      requestNotificationAuthorization(result: result)
    case "openAppSettings":
      openAppSettings(result: result)
    case "openNotificationSettings":
      openNotificationSettings(result: result)
    case "start":
      start(arguments: call.arguments, result: result)
    case "update":
      update(arguments: call.arguments, result: result)
    case "finish":
      finish(arguments: call.arguments, result: result)
    case "cancel":
      cancel(arguments: call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    notificationsEnabled = args["notificationsEnabled"] as? Bool ?? false
    refreshEnabled = args["refreshEnabled"] as? Bool ?? false
    beginBackgroundTask()
    if refreshEnabled { scheduleBackgroundTasks() }
    if args["liveActivityEnabled"] as? Bool ?? false {
      startLiveActivity(
        title: args["title"] as? String ?? "Kelivo",
        detail: args["detail"] as? String ?? "",
        tokenCount: args["tokenCount"] as? Int ?? 0,
        tokenLabel: args["tokenLabel"] as? String ?? ""
      )
    }
    result(true)
  }

  private func update(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    updateLiveActivity(
      detail: args["detail"] as? String ?? "",
      tokenCount: args["tokenCount"] as? Int ?? 0,
      tokenLabel: args["tokenLabel"] as? String ?? ""
    )
    result(true)
  }

  private func finish(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    let title = args["title"] as? String ?? "Kelivo"
    let detail = args["detail"] as? String ?? ""
    finishLiveActivity(title: title, detail: detail)
    if notificationsEnabled { showCompletionNotification(title: title, body: detail) }
    endBackgroundTask()
    resetGenerationOptions()
    result(true)
  }

  private func cancel(arguments: Any?, result: @escaping FlutterResult) {
    let args = arguments as? [String: Any] ?? [:]
    finishLiveActivity(
      title: liveActivityDisplayTitle.isEmpty ? "Kelivo" : liveActivityDisplayTitle,
      detail: args["detail"] as? String ?? ""
    )
    endBackgroundTask()
    resetGenerationOptions()
    result(true)
  }

  private func resetGenerationOptions() {
    notificationsEnabled = false
    refreshEnabled = false
  }

  private func getStatus(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        var liveActivitiesEnabled = false
        if #available(iOS 16.1, *) {
          liveActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        }
        result([
          "backgroundTaskActive": self.backgroundTask != .invalid,
          "liveActivityActive": self.isLiveActivityActive(),
          "notificationsAuthorized": settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional,
          "liveActivitiesEnabled": liveActivitiesEnabled,
        ])
      }
    }
  }

  private func requestNotificationAuthorization(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
      DispatchQueue.main.async { result(granted) }
    }
  }

  private func openAppSettings(result: @escaping FlutterResult) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in
      result(opened)
    }
  }

  private func openNotificationSettings(result: @escaping FlutterResult) {
    let url: URL?
    if #available(iOS 16.0, *) {
      url = URL(string: UIApplication.openNotificationSettingsURLString)
    } else {
      url = URL(string: UIApplication.openSettingsURLString)
    }
    guard let url else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in
      result(opened)
    }
  }

  private func beginBackgroundTask() {
    if backgroundTask != .invalid { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "KelivoBackgroundGeneration") { [weak self] in
      self?.endBackgroundTask()
    }
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }

  private func scheduleBackgroundTasks() {
    let refresh = BGAppRefreshTaskRequest(identifier: backgroundRefreshIdentifier)
    refresh.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    do {
      try BGTaskScheduler.shared.submit(refresh)
    } catch {
      NSLog("Kelivo background refresh schedule failed: \(error)")
    }

    let processing = BGProcessingTaskRequest(identifier: backgroundProcessingIdentifier)
    processing.requiresNetworkConnectivity = true
    processing.requiresExternalPower = false
    processing.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    do {
      try BGTaskScheduler.shared.submit(processing)
    } catch {
      NSLog("Kelivo background processing schedule failed: \(error)")
    }
  }

  private func handleBackgroundTask(_ task: BGTask) {
    if refreshEnabled { scheduleBackgroundTasks() }
    task.expirationHandler = { task.setTaskCompleted(success: false) }
    task.setTaskCompleted(success: true)
  }

  private func showCompletionNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(identifier: "kelivo.background-generation.\(Date().timeIntervalSince1970)", content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  private func isLiveActivityActive() -> Bool {
    if #available(iOS 16.1, *) {
      return liveActivity as? Activity<KelivoGenerationActivityAttributes> != nil
    }
    return false
  }

  private func startLiveActivity(title: String, detail: String, tokenCount: Int, tokenLabel: String) {
    if #available(iOS 16.1, *) {
      guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
      liveActivityDisplayTitle = title
      liveActivityDetail = detail
      liveActivityStartedAt = Date()
      liveActivityFinishedAt = nil
      liveActivityFinishedDetail = ""
      liveActivityFinished = false
      liveActivityWavePhase = 0
      liveActivityTokenCount = tokenCount
      liveActivityTokenLabel = tokenLabel
      let state = liveActivityState(
        displayTitle: title,
        detail: detail,
        tokenCount: tokenCount,
        tokenLabel: tokenLabel,
        finishedAt: nil,
        isFinished: false
      )
      do {
        if #available(iOS 16.2, *) {
          liveActivity = try Activity<KelivoGenerationActivityAttributes>.request(attributes: KelivoGenerationActivityAttributes(title: title), content: ActivityContent(state: state, staleDate: nil), pushType: nil)
        } else {
          liveActivity = try Activity<KelivoGenerationActivityAttributes>.request(attributes: KelivoGenerationActivityAttributes(title: title), contentState: state, pushType: nil)
        }
        startLiveActivityRefreshTimer()
      } catch {
        NSLog("Kelivo live activity start failed: \(error)")
        liveActivity = nil
      }
    }
  }

  private func updateLiveActivity(detail: String, tokenCount: Int, tokenLabel: String) {
    guard isLiveActivityActive(), !liveActivityFinished else { return }
    liveActivityTokenCount = tokenCount
    liveActivityTokenLabel = tokenLabel
    liveActivityDetail = detail
    liveActivityFinishedAt = nil
    liveActivityFinishedDetail = ""
  }

  func dismissFinishedLiveActivityIfNeeded() {
    guard liveActivityFinished else { return }
    endLiveActivity(detail: liveActivityFinishedDetail)
  }

  private func finishLiveActivity(title: String, detail: String) {
    liveActivityDisplayTitle = title
    liveActivityDetail = detail
    stopLiveActivityRefreshTimer()
    if UIApplication.shared.applicationState == .active {
      liveActivityFinishedAt = Date()
      liveActivityFinishedDetail = detail
      liveActivityFinished = true
      endLiveActivity(detail: detail)
      return
    }
    markLiveActivityFinished(title: title, detail: detail)
  }

  private func markLiveActivityFinished(title: String, detail: String) {
    if #available(iOS 16.1, *), let activity = liveActivity as? Activity<KelivoGenerationActivityAttributes> {
      let finishedAt = Date()
      liveActivityDisplayTitle = title
      liveActivityDetail = detail
      liveActivityFinishedAt = finishedAt
      liveActivityFinishedDetail = detail
      liveActivityFinished = true
      let state = liveActivityState(
        displayTitle: title,
        detail: detail,
        tokenCount: liveActivityTokenCount,
        tokenLabel: liveActivityTokenLabel,
        finishedAt: finishedAt,
        isFinished: true
      )
      Task {
        if #available(iOS 16.2, *) {
          await activity.update(ActivityContent(state: state, staleDate: nil))
        } else {
          await activity.update(using: state)
        }
      }
    }
  }

  private func endLiveActivity(detail: String) {
    if #available(iOS 16.1, *), let activity = liveActivity as? Activity<KelivoGenerationActivityAttributes> {
      let state = liveActivityState(
        displayTitle: liveActivityDisplayTitle,
        detail: detail,
        tokenCount: liveActivityTokenCount,
        tokenLabel: liveActivityTokenLabel,
        finishedAt: liveActivityFinishedAt,
        isFinished: liveActivityFinished
      )
      Task {
        if #available(iOS 16.2, *) {
          await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        } else {
          await activity.end(using: state, dismissalPolicy: .immediate)
        }
      }
      liveActivity = nil
      stopLiveActivityRefreshTimer()
      liveActivityDisplayTitle = ""
      liveActivityDetail = ""
      liveActivityTokenCount = 0
      liveActivityTokenLabel = ""
      liveActivityStartedAt = Date()
      liveActivityFinishedAt = nil
      liveActivityFinishedDetail = ""
      liveActivityFinished = false
      liveActivityWavePhase = 0
    }
  }

  private func startLiveActivityRefreshTimer() {
    stopLiveActivityRefreshTimer()
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      self?.refreshLiveActivity()
    }
    liveActivityRefreshTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func stopLiveActivityRefreshTimer() {
    liveActivityRefreshTimer?.invalidate()
    liveActivityRefreshTimer = nil
  }

  private func refreshLiveActivity() {
    guard #available(iOS 16.1, *), let activity = liveActivity as? Activity<KelivoGenerationActivityAttributes> else { return }
    guard !liveActivityFinished else { return }
    liveActivityWavePhase += 1
    let state = liveActivityState(
      displayTitle: liveActivityDisplayTitle,
      detail: liveActivityDetail,
      tokenCount: liveActivityTokenCount,
      tokenLabel: liveActivityTokenLabel,
      finishedAt: nil,
      isFinished: false
    )
    Task {
      if #available(iOS 16.2, *) {
        await activity.update(ActivityContent(state: state, staleDate: nil))
      } else {
        await activity.update(using: state)
      }
    }
  }

  @available(iOS 16.1, *)
  private func liveActivityState(
    displayTitle: String,
    detail: String,
    tokenCount: Int,
    tokenLabel: String,
    finishedAt: Date?,
    isFinished: Bool
  ) -> KelivoGenerationActivityAttributes.ContentState {
    let startedAt = liveActivityStartedAt
    let effectiveFinishedAt = finishedAt ?? Date()
    return KelivoGenerationActivityAttributes.ContentState(
      displayTitle: displayTitle,
      detail: detail,
      tokenCount: tokenCount,
      tokenLabel: tokenLabel,
      startedAt: startedAt,
      finishedAt: finishedAt,
      elapsedSeconds: isFinished
        ? elapsedSeconds(from: startedAt, to: effectiveFinishedAt)
        : elapsedSeconds(since: startedAt),
      wavePhase: liveActivityWavePhase,
      isFinished: isFinished
    )
  }

  private func elapsedSeconds(since startedAt: Date) -> Int {
    elapsedSeconds(from: startedAt, to: Date())
  }

  private func elapsedSeconds(from startedAt: Date, to endedAt: Date) -> Int {
    max(0, Int(endedAt.timeIntervalSince(startedAt)))
  }
}

private final class NativeFileSaveHandler: NSObject, UIDocumentPickerDelegate {
  weak var presentingViewController: UIViewController?
  private var pendingResult: FlutterResult?

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    if pendingResult != nil {
      result(FlutterError(code: "busy", message: "Another save operation is already in progress.", details: nil))
      return
    }

    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_args", message: "Arguments must be a map.", details: nil))
      return
    }

    let rawSourcePath = (args["sourcePath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !rawSourcePath.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Missing sourcePath.", details: nil))
      return
    }

    let sourceURL = URL(fileURLWithPath: rawSourcePath)
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      result(FlutterError(code: "not_found", message: "Source file does not exist.", details: nil))
      return
    }

    guard let presenter = topViewController(from: presentingViewController) else {
      result(FlutterError(code: "unavailable", message: "Unable to present document picker.", details: nil))
      return
    }

    pendingResult = result

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }

      let picker: UIDocumentPickerViewController
      if #available(iOS 14.0, *) {
        picker = UIDocumentPickerViewController(forExporting: [sourceURL], asCopy: true)
      } else {
        picker = UIDocumentPickerViewController(url: sourceURL, in: .exportToService)
      }

      picker.delegate = self
      picker.modalPresentationStyle = .formSheet
      if let popover = picker.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
      }

      presenter.present(picker, animated: true)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(with: false)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finish(with: !urls.isEmpty)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
    finish(with: true)
  }

  private func finish(with value: Bool) {
    let result = pendingResult
    pendingResult = nil
    result?(value)
  }

  private func topViewController(from controller: UIViewController?) -> UIViewController? {
    if let navigation = controller as? UINavigationController {
      return topViewController(from: navigation.visibleViewController)
    }
    if let tab = controller as? UITabBarController {
      return topViewController(from: tab.selectedViewController)
    }
    if let presented = controller?.presentedViewController {
      return topViewController(from: presented)
    }
    return controller
  }
}
