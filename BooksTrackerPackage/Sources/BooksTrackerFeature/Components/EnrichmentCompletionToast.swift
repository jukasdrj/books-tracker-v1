import SwiftUI

struct EnrichmentCompletionToast: View {
    let event: EnrichmentQueue.EnrichmentCompletionEvent
    @Binding var isPresented: Bool
    @Environment(TabCoordinator.self) private var tabCoordinator

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(event.successCount) \(event.successCount == 1 ? "book" : "books") updated")
                    .font(.subheadline.weight(.semibold))
                Text("New covers and metadata added")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 8)
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            // Auto-dismiss after 3 seconds
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation {
                    isPresented = false
                }
            }
        }
        .onTapGesture {
            tabCoordinator.showEnrichedBooksInLibrary(bookIDs: event.bookIds)
            isPresented = false
        }
    }
}
