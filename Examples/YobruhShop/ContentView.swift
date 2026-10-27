import Samvaad
import SwiftUI

/// Keeps the Help button's badge in step with the chat's unread count.
@MainActor
final class SupportBadge: ObservableObject {
    @Published private(set) var unread = 0

    nonisolated init() {}

    func start() {
        unread = Samvaad.unreadCount
        Samvaad.onUnreadChange = { [weak self] count in
            self?.unread = count
        }
    }
}

/// Stand-in for Yobruh's own API. The user hash is computed on the server
/// (HMAC-SHA256 of the lower-cased email with the identity secret); never in the app.
enum YobruhBackend {
    struct SamvaadIdentity: Decodable {
        let email: String
        let name: String
        let user_hash: String
    }

    static func samvaadIdentity() async throws -> SamvaadIdentity {
        let url = URL(string: "https://api.yobruh.in/me/samvaad-identity")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(SamvaadIdentity.self, from: data)
    }
}

struct ContentView: View {
    @StateObject private var support = SupportBadge()

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Yobruh Retail")
                    .font(.largeTitle.bold())
                Text("Order YB-1042 is on its way.")
                    .foregroundColor(.secondary)

                Button {
                    Samvaad.present(message: "Question about order YB-1042")
                } label: {
                    Label("Help", systemImage: "questionmark.bubble")
                        .padding(.horizontal, 8)
                        .overlay(alignment: .topTrailing) {
                            if support.unread > 0 {
                                Text("\(support.unread)")
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .padding(5)
                                    .background(Circle().fill(Color.red))
                                    .offset(x: 16, y: -14)
                                    .accessibilityLabel("\(support.unread) unread")
                            }
                        }
                }
                .buttonStyle(.borderedProminent)

                Button("Sign in") {
                    Task { @MainActor in
                        guard let me = try? await YobruhBackend.samvaadIdentity() else { return }
                        Samvaad.identify(email: me.email, name: me.name, userHash: me.user_hash)
                    }
                }

                Button("Sign out", role: .destructive) {
                    Samvaad.logout()
                }
            }
            .padding()
            .navigationTitle("Shop")
        }
        .onAppear { support.start() }
    }
}
