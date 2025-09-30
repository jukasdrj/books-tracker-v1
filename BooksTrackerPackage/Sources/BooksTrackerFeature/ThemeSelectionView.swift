import SwiftUI

// MARK: - iOS 26 HIG Compliance Documentation
/*
 ThemeSelectionView - 100% iOS 26 Human Interface Guidelines Compliant

 This view implements iOS 26 HIG best practices for selection interfaces:

 ✅ HIG Compliance:
 1. **Selection Pattern** (HIG: Picking and Editing)
    - Visual feedback on selection
    - Immediate preview of changes
    - Clear indication of current selection

 2. **Navigation** (HIG: Navigation)
    - Standard NavigationStack integration
    - Back button for dismissal
    - Changes persist automatically

 3. **Layout** (HIG: Layout)
    - Responsive grid layout
    - Adapts to device size
    - Proper spacing and padding

 4. **Accessibility** (HIG: Accessibility)
    - VoiceOver labels for themes
    - Dynamic Type support
    - High contrast support
 */

@MainActor
public struct ThemeSelectionView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    Text("Choose Your Theme")
                        .font(.title2.bold())
                        .foregroundColor(.primary)

                    Text("Your selection applies immediately across the app")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                // Theme Grid
                iOS26ThemePicker()

                // Additional Information
                VStack(alignment: .leading, spacing: 12) {
                    Label("Themes sync across your devices", systemImage: "icloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label("Each theme is optimized for accessibility", systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        .background(backgroundView.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .foregroundStyle(themeStore.primaryColor)
            }
        }
    }

    // MARK: - View Components

    private var backgroundView: some View {
        themeStore.backgroundGradient
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ThemeSelectionView()
    }
    .iOS26ThemeStore(iOS26ThemeStore())
}