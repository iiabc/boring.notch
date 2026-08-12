import AppKit
import SwiftUI

struct FloatingIsland {
    let id: String
    let height: CGFloat
    let content: AnyView

    init(id: String, height: CGFloat, @ViewBuilder content: () -> some View) {
        self.id = id
        self.height = height
        self.content = AnyView(content())
    }
}

@MainActor
final class IslandWindowManager {
    static let shared = IslandWindowManager()

    static let islandWidth: CGFloat = openNotchSize.width
    static let islandGap: CGFloat = 10
    static let contentInset: CGFloat = cornerRadiusInsets.opened.top + 12

    private(set) var isHoveringIsland = false

    private final class IslandContext {
        var windows: [NSWindow] = []
        weak var viewModel: BoringViewModel?
        var hoverCount = 0
        var isDismissing = false
    }

    private var contexts: [String: IslandContext] = [:]

    private init() {}

    func present(islands: [FloatingIsland], for viewModel: BoringViewModel) {
        let key = contextKey(for: viewModel)
        if let existing = contexts[key], !existing.windows.isEmpty, !existing.isDismissing {
            return
        }

        dismiss(for: key, animated: false)

        guard let screen = viewModel.screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) ?? NSScreen.main else {
            return
        }

        let context = IslandContext()
        context.viewModel = viewModel

        let screenFrame = screen.frame
        var topY = screenFrame.maxY - windowSize.height - Self.islandGap

        for (index, island) in islands.enumerated() {
            let frame = NSRect(
                x: screenFrame.midX - Self.islandWidth / 2,
                y: topY - island.height,
                width: Self.islandWidth,
                height: island.height
            )

            let window = BoringNotchSkyLightWindow(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.alphaValue = 0

            let wrapper = IslandAppearWrapper(index: index, onHover: { [weak self] hovering in
                self?.setHovering(hovering, for: key)
            }) {
                island.content
                    .padding(.horizontal, Self.contentInset)
            }
            window.contentView = NSHostingView(rootView: wrapper.preferredColorScheme(.dark))

            window.orderFrontRegardless()
            NotchSpaceManager.shared.notchSpace.windows.insert(window)
            context.windows.append(window)

            NSAnimationContext.runAnimationGroup { group in
                group.duration = 0.3
                group.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }

            topY -= island.height + Self.islandGap
        }

        contexts[key] = context
    }

    func dismiss(for viewModel: BoringViewModel, animated: Bool = true) {
        dismiss(for: contextKey(for: viewModel), animated: animated)
    }

    private func dismiss(for key: String, animated: Bool) {
        guard let context = contexts.removeValue(forKey: key), !context.windows.isEmpty else { return }
        context.isDismissing = true
        if context.hoverCount > 0 {
            context.hoverCount = 0
            updateHoveringFlag()
        }

        let windows = context.windows
        for window in windows {
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
        }

        if animated {
            NSAnimationContext.runAnimationGroup({ group in
                group.duration = 0.18
                group.timingFunction = CAMediaTimingFunction(name: .easeIn)
                for window in windows {
                    window.animator().alphaValue = 0
                }
            }, completionHandler: {
                for window in windows {
                    window.close()
                }
            })
        } else {
            for window in windows {
                window.close()
            }
        }
    }

    func dismissAll(animated: Bool = false) {
        for key in contexts.keys {
            dismiss(for: key, animated: animated)
        }
    }

    private func setHovering(_ hovering: Bool, for key: String) {
        guard let context = contexts[key], !context.isDismissing else { return }
        context.hoverCount = max(0, context.hoverCount + (hovering ? 1 : -1))
        updateHoveringFlag()

        if !hovering && context.hoverCount == 0 {
            let viewModel = context.viewModel
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, let viewModel, self.contexts[key] != nil else { return }
                guard viewModel.notchState == .open,
                      !self.isHoveringIsland,
                      !viewModel.isMouseHovering() else { return }
                viewModel.close()
            }
        }
    }

    private func updateHoveringFlag() {
        isHoveringIsland = contexts.values.contains { $0.hoverCount > 0 && !$0.isDismissing }
    }

    private func contextKey(for viewModel: BoringViewModel) -> String {
        viewModel.screenUUID ?? "main"
    }
}

private struct IslandAppearWrapper<Content: View>: View {
    let index: Int
    let onHover: (Bool) -> Void
    @ViewBuilder let content: Content
    @State private var appeared = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : -14)
            .scaleEffect(appeared ? 1 : 0.96, anchor: .top)
            .onAppear {
                withAnimation(.spring(duration: 0.5, bounce: 0.3).delay(Double(index) * 0.07)) {
                    appeared = true
                }
            }
            .onHover { onHover($0) }
    }
}
