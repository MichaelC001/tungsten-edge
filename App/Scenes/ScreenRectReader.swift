import AppKit
import SwiftUI

protocol ScreenRectDeliveryTask: AnyObject {
    func cancel()
}

protocol ScreenRectDeliveryScheduling: AnyObject {
    @discardableResult
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> ScreenRectDeliveryTask
}

private final class MainQueueScreenRectDeliveryScheduler: ScreenRectDeliveryScheduling {
    static let shared = MainQueueScreenRectDeliveryScheduler()

    @discardableResult
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> ScreenRectDeliveryTask {
        let work = DispatchWorkItem(block: action)
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            DispatchQueue.main.async(execute: work)
        }
        return work
    }
}

extension DispatchWorkItem: ScreenRectDeliveryTask {}

/// Reads a SwiftUI host's frame in AppKit screen coordinates. Delivery is asynchronous because
/// writing SwiftUI state synchronously from `layout()` is undefined.
struct ScreenRectReader: NSViewRepresentable {
    enum Delivery: Equatable {
        case immediateDeduplicated
        case debounced(settleInterval: TimeInterval)

        static let root: Delivery = .immediateDeduplicated
        static let tooltip: Delivery = .debounced(settleInterval: 0.05)
    }

    var delivery: Delivery = .root
    var scheduler: ScreenRectDeliveryScheduling = MainQueueScreenRectDeliveryScheduler.shared
    let onChange: (CGRect) -> Void

    func makeNSView(context: Context) -> NSView {
        TrackingView(delivery: delivery, scheduler: scheduler, onChange: onChange)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? TrackingView else { return }
        view.update(delivery: delivery, onChange: onChange)
        view.report()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? TrackingView)?.cancelPendingDelivery()
    }

    final class TrackingView: NSView {
        private var delivery: Delivery
        private let scheduler: ScreenRectDeliveryScheduling
        private var onChange: (CGRect) -> Void
        private var pendingRect: CGRect?
        private var lastQueuedImmediateRect: CGRect?
        private var lastReported: CGRect?
        private var pendingTasks: [UUID: ScreenRectDeliveryTask] = [:]
        private var deliveryGeneration: UInt64 = 0
        /// 宿主窗口移动 / 换屏的观察者，见 `observeWindowMovement`。
        private var windowObservers: [NSObjectProtocol] = []

        init(
            delivery: Delivery,
            scheduler: ScreenRectDeliveryScheduling = MainQueueScreenRectDeliveryScheduler.shared,
            onChange: @escaping (CGRect) -> Void
        ) {
            self.delivery = delivery
            self.scheduler = scheduler
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        deinit {
            pendingTasks.values.forEach { $0.cancel() }
            windowObservers.forEach(NotificationCenter.default.removeObserver)
        }

        func update(delivery: Delivery, onChange: @escaping (CGRect) -> Void) {
            if self.delivery != delivery {
                cancelPendingDelivery()
                lastReported = nil
                self.delivery = delivery
            }
            self.onChange = onChange
        }

        override func viewDidMoveToWindow() {
            observeWindowMovement()
            guard window != nil else {
                cancelPendingDelivery()
                return
            }
            report()
        }

        /// **窗口移动了也要重新上报。**
        ///
        /// `layout()` 只在**视图树**的布局发生变化时触发；把整个面板搬到另一块屏（悬停切屏）
        /// 或上下移动（边缘自动隐藏的收起 / 唤出）都不改变视图树，于是这里一次都不响，
        /// 每张卡缓存的屏幕矩形就停在旧位置上。实际后果：owner 2026-08-17 报「在一块屏上划过
        /// 图标，气泡有时弹到另一块没有任务条的屏上」——锚点还是换屏前那块屏的坐标。
        ///
        /// 观察者绑在**自己的宿主窗口**上（`object: window`），跟着 `viewDidMoveToWindow`
        /// 装拆，和既有的「detach 时取消所有排队投递」是同一套生命周期。
        private func observeWindowMovement() {
            windowObservers.forEach(NotificationCenter.default.removeObserver)
            windowObservers = []
            guard let window else { return }
            let center = NotificationCenter.default
            for name in [NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification] {
                windowObservers.append(
                    center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        self?.report()
                    }
                )
            }
        }

        override func layout() {
            super.layout()
            report()
        }

        func report() {
            guard let window else { return }
            enqueue(window.convertToScreen(convert(bounds, to: nil)))
        }

        func enqueue(_ rect: CGRect) {
            switch delivery {
            case .immediateDeduplicated:
                guard rect != lastQueuedImmediateRect else { return }
                lastQueuedImmediateRect = rect
                schedule(after: 0) { [weak self] in self?.deliverIfChanged(rect) }

            case let .debounced(settleInterval):
                guard rect != pendingRect,
                      !(pendingTasks.isEmpty && rect == lastReported) else { return }
                cancelScheduledTasks(incrementGeneration: true)
                pendingRect = rect
                schedule(after: settleInterval) { [weak self] in
                    self?.pendingRect = nil
                    self?.deliverIfChanged(rect)
                }
            }
        }

        func cancelPendingDelivery() {
            cancelScheduledTasks(incrementGeneration: true)
            pendingRect = nil
            lastQueuedImmediateRect = nil
        }

        private func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
            let id = UUID()
            let generation = deliveryGeneration
            let task = scheduler.schedule(after: delay) { [weak self] in
                guard let self else { return }
                self.pendingTasks.removeValue(forKey: id)
                guard self.deliveryGeneration == generation else { return }
                action()
            }
            pendingTasks[id] = task
        }

        private func cancelScheduledTasks(incrementGeneration: Bool) {
            pendingTasks.values.forEach { $0.cancel() }
            pendingTasks.removeAll()
            if incrementGeneration { deliveryGeneration &+= 1 }
        }

        private func deliverIfChanged(_ rect: CGRect) {
            guard rect != lastReported else { return }
            lastReported = rect
            onChange(rect)
        }
    }
}
