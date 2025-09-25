import SwiftUI
import SwiftData

/// Single Book Detail View - iOS 26 Immersive Design
/// Features blurred cover art background with floating metadata card
struct WorkDetailView: View {
    let work: Work

    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var selectedEdition: Edition?
    @State private var showingEditionPicker = false

    // Primary edition for display
    private var primaryEdition: Edition {
        selectedEdition ?? work.primaryEdition ?? work.availableEditions.first ?? placeholderEdition
    }

    // Placeholder edition for works without editions
    private var placeholderEdition: Edition {
        Edition(work: work)
    }

    var body: some View {
        ZStack {
            // MARK: - Immersive Background
            immersiveBackground

            // MARK: - Main Content
            mainContent
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 32, height: 32)
                        }
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                if work.availableEditions.count > 1 {
                    Button("Editions") {
                        showingEditionPicker.toggle()
                    }
                    .foregroundColor(.white)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .frame(height: 32)
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .onAppear {
            selectedEdition = work.primaryEdition
        }
        .sheet(isPresented: $showingEditionPicker) {
            EditionPickerView(
                work: work,
                selectedEdition: Binding(
                    get: { selectedEdition ?? primaryEdition },
                    set: { selectedEdition = $0 }
                )
            )
            .iOS26SheetGlass()
        }
    }

    // MARK: - Immersive Background

    private var immersiveBackground: some View {
        GeometryReader { geometry in
            ZStack {
                // Blurred cover art background
                AsyncImage(url: primaryEdition.coverImageURL.flatMap(URL.init)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .blur(radius: 20)
                        .overlay {
                            // Color shift overlay
                            LinearGradient(
                                colors: [
                                    themeStore.primaryColor.opacity(0.3),
                                    themeStore.secondaryColor.opacity(0.2),
                                    Color.black.opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                } placeholder: {
                    // Fallback gradient background
                    LinearGradient(
                        colors: [
                            themeStore.primaryColor.opacity(0.6),
                            themeStore.secondaryColor.opacity(0.4),
                            Color.black.opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Top spacer for navigation bar
                Color.clear.frame(height: 60)

                // MARK: - Book Cover Hero
                bookCoverHero

                // MARK: - Edition Metadata Card
                EditionMetadataView(work: work, edition: primaryEdition)
                    .padding(.horizontal, 20)

                // Bottom padding
                Color.clear.frame(height: 40)
            }
        }
    }

    private var bookCoverHero: some View {
        VStack(spacing: 16) {
            // Large cover image
            AsyncImage(url: primaryEdition.coverImageURL.flatMap(URL.init)) { image in
                image
                    .resizable()
                    .aspectRatio(2/3, contentMode: .fill)
                    .frame(width: 200, height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            } placeholder: {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(
                        colors: [
                            themeStore.primaryColor.opacity(0.4),
                            themeStore.secondaryColor.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 200, height: 300)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "book.closed")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.8))

                            Text(work.title)
                                .font(.headline.bold())
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .padding(.horizontal)
                        }
                    }
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            }

            // Work title and author (large, readable)
            VStack(spacing: 8) {
                Text(work.title)
                    .font(.title.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                Text(work.authorNames)
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Edition Picker View

struct EditionPickerView: View {
    let work: Work
    @Binding var selectedEdition: Edition
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(work.availableEditions, id: \.id) { edition in
                Button(action: {
                    selectedEdition = edition
                    dismiss()
                }) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Edition title or format
                        Text(edition.editionTitle ?? edition.format.displayName)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)

                        // Publisher info
                        if !edition.publisherInfo.isEmpty {
                            Text(edition.publisherInfo)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Format and pages
                        HStack {
                            Label(edition.format.displayName, systemImage: edition.format.icon)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if let pageCount = edition.pageCountString {
                                Spacer()
                                Text(pageCount)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // ISBN
                        if let isbn = edition.primaryISBN {
                            Text("ISBN: \(isbn)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    edition.id == selectedEdition.id ?
                    Color.blue.opacity(0.1) : Color.clear
                )
            }
            .navigationTitle("Choose Edition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let container = try! ModelContainer(for: Work.self, Edition.self, UserLibraryEntry.self, Author.self)

    let context = container.mainContext

    // Sample data
    let author = Author(name: "Kazuo Ishiguro", culturalRegion: .asia)
    let work = Work(
        title: "Klara and the Sun",
        authors: [author],
        originalLanguage: "English",
        firstPublicationYear: 2021
    )
    let edition = Edition(
        isbn: "9780571364893",
        publisher: "Faber & Faber",
        publicationDate: "2021",
        pageCount: 303,
        format: .hardcover,
        work: work
    )

    context.insert(author)
    context.insert(work)
    context.insert(edition)

    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    return NavigationStack {
        WorkDetailView(work: work)
    }
    .modelContainer(container)
    .environment(\.iOS26ThemeStore, themeStore)
}