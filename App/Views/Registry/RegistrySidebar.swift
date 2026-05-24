import SwiftUI

struct RegistrySidebar: View {
    @Bindable var model: RegistryModel
    @Environment(\.appStrings) private var strings

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(strings("Search skills"), text: $model.searchInput)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            .padding(8)
            .help(strings("Search registry skills"))

            // Category tabs (hidden when searching)
            if model.searchInput.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 4) {
                    ForEach(LeaderboardCategory.allCases, id: \.self) { c in
                        Button {
                            model.category = c
                        } label: {
                            Text(label(for: c))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    model.category == c
                                        ? Color.accentColor.opacity(0.3) : .clear
                                )
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help(help(for: c))
                    }
                    Spacer()
                    if model.totalCount > 0 {
                        Text("\(model.totalCount)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            // List
            if model.isLoading {
                ProgressView().padding()
                Spacer()
            } else if let listError = model.listError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        strings("Unable to load skills"),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.callout)
                    Text(listError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button(strings("Retry")) {
                        Task { await retry() }
                    }
                    .help(strings("Retry loading skills"))
                }
                .padding()
                Spacer()
            } else if model.skills.isEmpty {
                Text(
                    model.searchInput.isEmpty
                        ? strings("No skills available")
                        : strings("No results")
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.skills) { skill in
                            Button {
                                model.beginSelect(id: skill.id)
                            } label: {
                                RegistryRow(skill: skill, isSelected: model.selectedID == skill.id)
                            }
                            .buttonStyle(.plain)
                            .help(strings("Show skill details"))
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func retry() async {
        if model.searchInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await model.loadLeaderboard()
        } else {
            await model.runSearchNow()
        }
    }

    private func label(for c: LeaderboardCategory) -> String {
        switch c {
        case .allTime: return strings("All Time")
        case .trending: return strings("Trending")
        case .hot: return strings("Hot")
        }
    }

    private func help(for c: LeaderboardCategory) -> String {
        switch c {
        case .allTime: return strings("Show all-time leaderboard")
        case .trending: return strings("Show trending skills")
        case .hot: return strings("Show hot skills")
        }
    }
}
