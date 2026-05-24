import SwiftUI

struct RegistrySidebar: View {
    @Bindable var model: RegistryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appStrings) private var strings

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(strings("Search skills"), text: $model.searchInput)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .padding(8)
            .help(strings("Search registry skills"))

            if model.searchInput.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 8) {
                    Picker(strings("Registry category"), selection: categoryBinding) {
                        ForEach(LeaderboardCategory.allCases, id: \.self) { c in
                            Text(label(for: c)).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help(strings("Choose registry category"))

                    Spacer()

                    if model.totalCount > 0 {
                        Text("\(model.totalCount)")
                            .font(.caption2).foregroundStyle(.secondary)
                            .monospacedDigit()
                            .help(strings("\(model.totalCount) skills"))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

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
                ContentUnavailableView(
                    model.searchInput.isEmpty ? strings("No skills available") : strings("No results"),
                    systemImage: model.searchInput.isEmpty ? "books.vertical" : "magnifyingglass",
                    description: Text(
                        model.searchInput.isEmpty
                            ? strings("Try another category or retry loading the registry.")
                            : strings("Check spelling or search for a shorter skill name.")
                    )
                )
                .padding()
                Spacer()
            } else {
                List(selection: selectionBinding) {
                    ForEach(model.skills) { skill in
                        RegistryRow(skill: skill)
                            .tag(skill.id)
                            .help(strings("Show skill details"))
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .animation(microAnimation, value: model.selectedID)
        .animation(microAnimation, value: model.category)
        .animation(
            microAnimation,
            value: model.searchInput.trimmingCharacters(in: .whitespaces).isEmpty
        )
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { model.selectedID },
            set: { newID in
                guard let newID, newID != model.selectedID else { return }
                withMotion {
                    _ = model.beginSelect(id: newID)
                }
            }
        )
    }

    private var categoryBinding: Binding<LeaderboardCategory> {
        Binding(
            get: { model.category },
            set: { newCategory in
                withMotion {
                    model.category = newCategory
                }
            }
        )
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

    private var microAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.18)
    }

    private func withMotion(_ action: () -> Void) {
        if reduceMotion {
            action()
        } else {
            withAnimation(.snappy(duration: 0.18), action)
        }
    }
}
