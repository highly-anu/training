import SwiftUI
import Combine
import UIKit

/// Sharing a method, the program or a session from the phone (design-system
/// §6.63; docs/roadmap.md item 25): the server makes the link, the system's
/// share sheet takes it. One `LinkSharer` a screen (`@StateObject`), its
/// sheet and its failure attached with `.sharesLinks(_:)`, and
/// `sharer.share(_:with:)` from whichever button or menu item offers it.
@MainActor
final class LinkSharer: ObservableObject {
    @Published var link: ShareLinkInfo? = nil
    @Published var failure: String? = nil
    @Published private(set) var isWorking = false

    func share(_ request: ShareRequest, with api: APIClient?) {
        guard let api, !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                link = try await api.createShare(request)
            } catch APIError.serverErrorDetail(_, let detail) {
                failure = detail
            } catch {
                failure = "The link could not be made. Try again."
            }
        }
    }
}

private struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL
    let title: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.title = title
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension View {
    /// The share sheet for the link a `LinkSharer` made, and why one could not be made.
    func sharesLinks(_ sharer: LinkSharer) -> some View {
        self
            .sheet(item: Binding(get: { sharer.link }, set: { sharer.link = $0 })) { link in
                if let url = URL(string: link.url) {
                    ActivitySheet(url: url, title: link.title ?? "Shared link")
                }
            }
            .alert("Could not share", isPresented: Binding(get: { sharer.failure != nil },
                                                             set: { if !$0 { sharer.failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sharer.failure ?? "")
            }
    }
}

/// The athlete's own links (Settings ▸ Account ▸ Shared links): what each is,
/// when it was shared, and Remove — which stops it for everyone who has it.
struct SharedLinksView: View {
    @EnvironmentObject var appState: AppState

    @State private var links: [ShareLinkInfo] = []
    @State private var isLoading = true
    @State private var error: String? = nil
    @StateObject private var sharer = LinkSharer()

    var body: some View {
        Group {
            switch AppLoadPhase.resolve(hasContent: !links.isEmpty, isLoading: isLoading, error: error) {
            case .loading:
                ProgressView()
            case .failed(let message):
                AppFailedState(title: "Could not load your links", message: message) { await load() }
            case .empty:
                AppEmptyState(icon: "link", title: "Nothing shared yet",
                              message: "Share a session, a method or your program from where you read it.")
            case .content:
                List {
                    Section {
                        ForEach(links) { link in
                            Button { sharer.link = link } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(link.title ?? ShareWords.listKind(link.kind)).foregroundStyle(.primary)
                                    Text([ShareWords.listKind(link.kind), ShareWords.day(link.createdAt)]
                                        .compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) { Task { await remove(link) } }
                            }
                            .contextMenu {
                                Button(role: .destructive) { Task { await remove(link) } } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("Anyone with a link can open it. It keeps showing what it showed when you shared it, even after you change or delete what it came from, until you remove it. Swipe a link to remove it.")
                    }
                }
            }
        }
        .navigationTitle("Shared links")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sharesLinks(sharer)
    }

    private func load() async {
        guard let api = appState.api else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            links = try await api.fetchShares()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(_ link: ShareLinkInfo) async {
        guard let api = appState.api else { return }
        do {
            try await api.revokeShare(link.token)
            links.removeAll { $0.token == link.token }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
