import SwiftUI

@available(iOS 26.0, *)
struct AlphabeticalIndexView: View {
    let works: [Work]
    let scrollProxy: ScrollViewProxy

    private var indexLetters: [String] {
        let firstLetters = works.compactMap { $0.title.first?.uppercased() }
        let uniqueLetters = Array(Set(firstLetters)).sorted()
        return uniqueLetters
    }

    var body: some View {
        VStack {
            ForEach(indexLetters, id: \.self) { letter in
                Button(action: {
                    if let work = works.first(where: { $0.title.uppercased().starts(with: letter) }) {
                        withAnimation {
                            scrollProxy.scrollTo(work.id, anchor: .top)
                        }
                    }
                }) {
                    Text(letter)
                        .font(.system(size: 12, weight: .bold))
                        .padding(.vertical, 2)
                        .padding(.horizontal, 4)
                }
            }
        }
        .padding(4)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
    }
}
