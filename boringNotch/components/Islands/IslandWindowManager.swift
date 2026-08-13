import AppKit
import Defaults
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

    var isMouseOverIsland: Bool {
        let location = NSEvent.mouseLocation
        return contexts.values.contains { context in
            guard !context.isDismissing, let window = context.window else { return false }
            return window.frame.contains(location)
        }
    }

    final class IslandStackPresentation: ObservableObject {
        @Published var presented: [Bool]

        init(count: Int) {
            presented = Array(repeating: false, count: count)
        }
    }

    private final class IslandContext {
        var window: NSWindow?
        var presentation: IslandStackPresentation?
        weak var viewModel: BoringViewModel?
        var islandCount = 0
        var hoverCount = 0
        var isDismissing = false
    }

    private var contexts: [String: IslandContext] = [:]

    private init() {}

    func present(islands: [FloatingIsland], for viewModel: BoringViewModel) {
        let key = contextKey(for: viewModel)
        if let existing = contexts[key] {
            if !existing.isDismissing, existing.window != nil {
                return
            }
            if let staleWindow = existing.window {
                NotchSpaceManager.shared.notchSpace.windows.remove(staleWindow)
                staleWindow.close()
            }
            contexts.removeValue(forKey: key)
        }

        guard !islands.isEmpty,
              let screen = viewModel.screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) ?? NSScreen.main else {
            return
        }

        let screenFrame = screen.frame
        let notchBottomY = screenFrame.maxY - windowSize.height
        let totalHeight = islands.reduce(0) { $0 + $1.height }
            + Self.islandGap * CGFloat(islands.count - 1)

        let frame = NSRect(
            x: screenFrame.midX - Self.islandWidth / 2,
            y: notchBottomY - Self.islandGap - totalHeight,
            width: Self.islandWidth,
            height: totalHeight
        )

        let window = BoringNotchSkyLightWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let presentation = IslandStackPresentation(count: islands.count)
        let container = IslandStackContainerView(
            islands: islands,
            presentation: presentation,
            onHover: { [weak self] hovering in
                self?.setHovering(hovering, for: key)
            }
        )
        window.contentView = NSHostingView(rootView: container.preferredColorScheme(.dark))

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)

        let context = IslandContext()
        context.window = window
        context.presentation = presentation
        context.viewModel = viewModel
        context.islandCount = islands.count
        contexts[key] = context

        for index in islands.indices {
            withAnimation(StandardAnimations.open.delay(Double(index) * 0.07)) {
                presentation.presented[index] = true
            }
        }
    }

    func dismiss(for viewModel: BoringViewModel, animated: Bool = true) {
        dismiss(for: contextKey(for: viewModel), animated: animated)
    }

    private func dismiss(for key: String, animated: Bool) {
        guard let context = contexts[key], let window = context.window, !context.isDismissing else { return }
        context.isDismissing = true
        if context.hoverCount > 0 {
            context.hoverCount = 0
            updateHoveringFlag()
        }

        NotchSpaceManager.shared.notchSpace.windows.remove(window)

        if animated, let presentation = context.presentation {
            let stagger: TimeInterval = 0.06
            for index in presentation.presented.indices {
                let delay = Double(presentation.presented.count - 1 - index) * stagger
                withAnimation(StandardAnimations.close.delay(delay)) {
                    presentation.presented[index] = false
                }
            }
            let settle = 0.45 / Defaults[.animationSpeedMultiplier]
                + Double(context.islandCount) * stagger + 0.1
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(settle * 1000)))
                window.close()
                if let self, self.contexts[key] === context {
                    self.contexts.removeValue(forKey: key)
                }
            }
        } else {
            window.close()
            contexts.removeValue(forKey: key)
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
                      !self.isMouseOverIsland,
                      !viewModel.isBatteryPopoverActive,
                      !viewModel.isProcessDetailPopoverActive,
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

private struct IslandStackContainerView: View {
    let islands: [FloatingIsland]
    @ObservedObject var presentation: IslandWindowManager.IslandStackPresentation
    let onHover: (Bool) -> Void

    var body: some View {
        VStack(spacing: IslandWindowManager.islandGap) {
            ForEach(Array(islands.enumerated()), id: \.element.id) { index, island in
                IslandRevealView(
                    island: island,
                    isPresented: presentation.presented[index]
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onHover { onHover($0) }
    }
}

private struct IslandRevealView: View {
    let island: FloatingIsland
    let isPresented: Bool

    private let collapsedWidth: CGFloat = 200
    private var fullWidth: CGFloat {
        IslandWindowManager.islandWidth - 2 * IslandWindowManager.contentInset
    }

    var body: some View {
        island.content
            .frame(width: fullWidth, height: island.height)
            .frame(
                width: isPresented ? fullWidth : collapsedWidth,
                height: isPresented ? island.height : 0,
                alignment: .top
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadiusInsets.opened.bottom, style: .continuous))
    }
}
