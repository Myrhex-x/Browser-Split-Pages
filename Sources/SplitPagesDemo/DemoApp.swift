//
//  DemoApp.swift
//  SplitPagesDemo
//
//  A small browser to try SplitPages with: one page, ⌘\ (or the split button) to open a second
//  one beside it, the hinge to share the room, and ⌘\ again to fold back to the page with the
//  keyboard. The new side asks what goes there: a few sites, or any address or search.
//
//  Run it with `swift run SplitPagesDemo`, or build an app with scripts/make-demo-app.sh.
//

import AppKit
import Observation
import SplitPages
import SwiftUI
import WebKit

@main
struct SplitPagesDemoApp: App {
    @NSApplicationDelegateAdaptor(DemoDelegate.self) private var delegate
    @State private var model = DemoModel()

    var body: some Scene {
        WindowGroup("Split Pages") {
            DemoView(model: model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .sidebar) {
                Button(model.split.isSplit ? "Back to One Page" : "Split Pages") { model.split.toggle() }
                    .keyboardShortcut("\\")
                Button("Share the Room Evenly") { withAnimation(.smooth) { model.split.center() } }
                    .disabled(!model.split.isSplit)
            }
        }
    }
}

/// A command-line build has no app bundle: this makes it a regular app with a window and a menu bar.
final class DemoDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Model

/// One side's page: its web view, kept for as long as the side is.
@MainActor
@Observable
final class PageModel {
    var address = ""
    var title = ""
    /// The new side, before it has a page.
    var choosing: Bool
    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(url: URL?) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        choosing = url == nil
        observations = [
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.address = view.url?.absoluteString ?? "" }
            },
            webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.title = view.title ?? "" }
            },
        ]
        if let url { webView.load(URLRequest(url: url)) }
    }

    /// An address, or a search on DuckDuckGo.
    func open(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url: URL?
        if trimmed.contains("."), !trimmed.contains(" ") {
            url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed)
        } else {
            var components = URLComponents(string: "https://duckduckgo.com/")
            components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
            url = components?.url
        }
        guard let url else { return }
        choosing = false
        webView.load(URLRequest(url: url))
    }
}

@MainActor
@Observable
final class DemoModel {
    let split = SplitPagesState()
    var leading = PageModel(url: URL(string: "https://en.wikipedia.org/wiki/Foldable_smartphone"))
    var trailing = PageModel(url: nil)

    init() {
        // The side that folds away starts over, asking what goes there next time.
        split.onFold = { [weak self] side in
            guard let self else { return }
            if side == .trailing { self.trailing = PageModel(url: nil) } else { self.leading = PageModel(url: nil) }
        }
    }

    var focusedPage: PageModel { split.focused == .leading ? leading : trailing }
}

// MARK: - Views

struct DemoView: View {
    @Bindable var model: DemoModel

    var body: some View {
        VStack(spacing: 0) {
            DemoToolbar(model: model)
                .frame(height: 52)
            SplitPagesView(state: model.split) {
                PageView(page: model.leading)
            } trailing: {
                PageView(page: model.trailing)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .padding([.horizontal, .bottom], 8)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct DemoToolbar: View {
    @Bindable var model: DemoModel
    @State private var text = ""

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 70, height: 1)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search or enter an address", text: $text)
                    .textFieldStyle(.plain)
                    .onSubmit { model.focusedPage.open(text) }
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            Button {
                model.split.toggle()
            } label: {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(model.split.isSplit ? Color.primary.opacity(0.1) : .clear))
            }
            .buttonStyle(.plain)
            .help(model.split.isSplit ? "Back to one page (⌘\\)" : "Split pages (⌘\\)")
        }
        .padding(.horizontal, 10)
        .onChange(of: model.focusedPage.address, initial: true) { _, address in text = address }
        .onChange(of: model.split.focused) { _, _ in text = model.focusedPage.address }
    }
}

/// A side: its page, or the choice of what goes there.
private struct PageView: View {
    @Bindable var page: PageModel

    var body: some View {
        ZStack {
            WebViewHost(webView: page.webView)
            if page.choosing {
                Chooser(page: page)
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: page.choosing)
    }
}

private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if webView.superview !== container { attach(to: container) }
    }

    private func attach(to container: NSView) {
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}

/// What goes on the new side: a few sites, or anything typed.
private struct Chooser: View {
    @Bindable var page: PageModel
    @State private var text = ""
    @FocusState private var focused: Bool

    private static let sites: [(name: String, address: String, symbol: String)] = [
        ("Wikipedia", "https://www.wikipedia.org", "book"),
        ("Hacker News", "https://news.ycombinator.com", "newspaper"),
        ("GitHub", "https://github.com", "chevron.left.forwardslash.chevron.right"),
        ("Apple", "https://www.apple.com", "applelogo"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What goes on this side?")
                        .font(.system(size: 24, weight: .semibold))
                    Text("A site, a search or an address.")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search or enter an address", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($focused)
                        .onSubmit { page.open(text) }
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(Self.sites, id: \.address) { site in
                        Button { page.open(site.address) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: site.symbol).font(.system(size: 20))
                                Text(site.name).font(.system(size: 13, weight: .medium))
                            }
                            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Drag the line between the pages to share the room, or nearly to an edge to fold a page away. ⌘\\ folds them back into one.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(28)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true } }
    }
}
