import SwiftUI

// MARK: - iOS 26 Morphing Search Bar

public struct iOS26MorphingSearchBar: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.colorScheme) private var colorScheme
    @Binding var searchText: String
    @Binding var isSearching: Bool

    let onSearchSubmit: () -> Void
    let onClear: () -> Void

    @State private var isExpanded: Bool = false
    @State private var isFocused: Bool = false
    @FocusState private var searchFieldFocused: Bool

    // Search suggestions
    let suggestions: [String]
    let onSuggestionTap: (String) -> Void

    public init(
        searchText: Binding<String>,
        isSearching: Binding<Bool>,
        suggestions: [String] = [],
        onSearchSubmit: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onSuggestionTap: @escaping (String) -> Void = { _ in }
    ) {
        self._searchText = searchText
        self._isSearching = isSearching
        self.suggestions = suggestions
        self.onSearchSubmit = onSearchSubmit
        self.onClear = onClear
        self.onSuggestionTap = onSuggestionTap
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchBarContent

            if shouldShowSuggestions {
                suggestionsView
                    .transition(.asymmetric(
                        insertion: .push(from: .top).combined(with: .opacity),
                        removal: .push(from: .bottom).combined(with: .opacity)
                    ))
            }
        }
        .animation(.smooth(duration: 0.4), value: isFocused)
        .animation(.smooth(duration: 0.4), value: isExpanded)
        .animation(.smooth(duration: 0.3), value: shouldShowSuggestions)
    }

    // MARK: - Search Bar Content

    private var searchBarContent: some View {
        HStack(spacing: 12) {
            // Search Icon or Loading Indicator
            searchIconOrSpinner

            // Search TextField
            searchTextField

            // Clear/Cancel Button
            if !searchText.isEmpty || isFocused {
                clearButton
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.6).combined(with: .opacity)
                    ))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            searchBarBackground
        }
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 16 : 25))
        .scaleEffect(isExpanded ? 1.0 : 0.95)
        .shadow(
            color: themeStore.primaryColor.opacity(0.2),
            radius: isExpanded ? 12 : 6,
            x: 0,
            y: isExpanded ? 4 : 2
        )
        .onTapGesture {
            if !isFocused {
                expandAndFocus()
            }
        }
    }

    private var searchIconOrSpinner: some View {
        Group {
            if isSearching {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(themeStore.primaryColor)
            } else {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(isFocused ? themeStore.primaryColor : .secondary)
                    .font(.system(size: 18, weight: .medium))
            }
        }
        .frame(width: 20, height: 20)
        .animation(.smooth(duration: 0.3), value: isSearching)
        .animation(.smooth(duration: 0.3), value: isFocused)
    }

    private var searchTextField: some View {
        TextField("Search books, authors, ISBN...", text: $searchText)
            .focused($searchFieldFocused)
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(colorScheme == .dark ? .white : .primary)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit {
                onSearchSubmit()
            }
            .onChange(of: searchFieldFocused) { oldValue, newValue in
                withAnimation(.smooth(duration: 0.4)) {
                    isFocused = newValue
                    isExpanded = newValue
                }
            }
            .onChange(of: searchText) { oldValue, newValue in
                // Auto-trigger search as user types (handled by SearchModel with debouncing)
            }
    }

    private var clearButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) {
                searchText = ""
                onClear()
            }

            // Provide haptic feedback
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 18, weight: .medium))
        }
        .buttonStyle(.plain)
    }

    private var searchBarBackground: some View {
        ZStack {
            // Base glass material
            RoundedRectangle(cornerRadius: isExpanded ? 16 : 25)
                .fill(.ultraThinMaterial)

            // Themed glass tint
            RoundedRectangle(cornerRadius: isExpanded ? 16 : 25)
                .fill(themeStore.glassStint(intensity: isFocused ? 0.15 : 0.08))

            // Subtle border
            RoundedRectangle(cornerRadius: isExpanded ? 16 : 25)
                .strokeBorder(
                    themeStore.primaryColor.opacity(isFocused ? 0.3 : 0.1),
                    lineWidth: isFocused ? 1.5 : 1
                )
        }
    }

    // MARK: - Suggestions View

    private var shouldShowSuggestions: Bool {
        isFocused && !suggestions.isEmpty && searchText.count >= 2
    }

    private var suggestionsView: some View {
        VStack(spacing: 8) {
            ForEach(suggestions, id: \.self) { suggestion in
                suggestionRow(suggestion)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Rectangle()
                        .fill(themeStore.glassStint(intensity: 0.05))
                }
        }
    }

    private func suggestionRow(_ suggestion: String) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) {
                searchText = suggestion
                onSuggestionTap(suggestion)
                searchFieldFocused = false
            }

            // Haptic feedback
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14, weight: .medium))

                Text(suggestion)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.left")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.clear)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helper Methods

    private func expandAndFocus() {
        withAnimation(.smooth(duration: 0.4)) {
            isExpanded = true
            isFocused = true
        }

        // Delay focus to allow animation to start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            searchFieldFocused = true
        }

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
}

// MARK: - Search Bar Placement Modifier

public struct SearchBarPlacement: ViewModifier {
    let placement: SearchPlacement
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public func body(content: Content) -> some View {
        switch placement {
        case .automatic:
            if horizontalSizeClass == .compact {
                // iPhone: Bottom-aligned ergonomic placement
                VStack(spacing: 0) {
                    Spacer()
                    content
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            } else {
                // iPad: Top navigation area
                VStack(spacing: 0) {
                    content
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    Spacer()
                }
            }

        case .top:
            VStack(spacing: 0) {
                content
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                Spacer()
            }

        case .bottom:
            VStack(spacing: 0) {
                Spacer()
                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

        case .navigation:
            content
                .padding(.horizontal, 16)
        }
    }
}

public enum SearchPlacement {
    case automatic  // Adapts to device (bottom on iPhone, top on iPad)
    case top        // Always top
    case bottom     // Always bottom
    case navigation // In navigation area
}

// MARK: - View Extension

extension View {
    public func searchBarPlacement(_ placement: SearchPlacement) -> some View {
        modifier(SearchBarPlacement(placement: placement))
    }
}

// MARK: - Preview

#Preview("Morphing Search Bar") {
    @Previewable @State var searchText = ""
    @Previewable @State var isSearching = false

    let sampleSuggestions = [
        "Stephen King",
        "Harry Potter",
        "The Martian",
        "Agatha Christie"
    ]

    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    return NavigationStack {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack {
                iOS26MorphingSearchBar(
                    searchText: $searchText,
                    isSearching: $isSearching,
                    suggestions: searchText.count >= 2 ? sampleSuggestions : [],
                    onSearchSubmit: {
                        print("Search submitted: \(searchText)")
                        isSearching = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            isSearching = false
                        }
                    },
                    onClear: {
                        print("Search cleared")
                    },
                    onSuggestionTap: { suggestion in
                        print("Suggestion tapped: \(suggestion)")
                    }
                )

                Spacer()

                // Demo controls
                VStack(spacing: 16) {
                    Button("Toggle Searching") {
                        isSearching.toggle()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Set Sample Text") {
                        searchText = "Harry Potter"
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
        .environment(\.iOS26ThemeStore, themeStore)
    }
}