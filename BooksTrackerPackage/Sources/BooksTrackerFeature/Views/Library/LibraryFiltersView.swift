import SwiftUI

@available(iOS 26.0, *)
struct LibraryFiltersView: View {
    @Binding var selectedAuthor: Author?
    @Binding var selectedRegion: CulturalRegion?
    @Binding var yearRange: ClosedRange<Int>?

    // Add bindings for other filters here in the future

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Author")) {
                    Text("Author filter will go here")
                }

                Section(header: Text("Cultural Region")) {
                    Text("Cultural region filter will go here")
                }

                Section(header: Text("Publication Year")) {
                    Text("Publication year filter will go here")
                }

                Section(header: Text("Rating")) {
                    Text("Rating filter will go here")
                }

                Section(header: Text("Reading Status")) {
                    Text("Reading status filter will go here")
                }
            }
            .navigationTitle("Filters")
            .navigationBarItems(trailing: Button("Done") {
                // Dismiss the sheet
            })
        }
    }
}
