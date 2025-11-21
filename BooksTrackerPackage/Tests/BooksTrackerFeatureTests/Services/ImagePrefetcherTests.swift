import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("ImagePrefetcher")
struct ImagePrefetcherTests {
    @Test("cancelPrefetching clears task and is idempotent")
    func cancelPrefetching_isIdempotent() async throws {
        let prefetcher = await ImagePrefetcher()

        // Starting without URLs should still create/cancel safely
        await prefetcher.startPrefetching(urls: [])
        await prefetcher.cancelPrefetching()
        // Second cancel should not crash
        await prefetcher.cancelPrefetching()

        // Start again with a fake URL that will fail fast but spawn a task
        let url = URL(string: "https://invalid.localhost/does-not-exist.jpg")!
        await prefetcher.startPrefetching(urls: [url])
        await prefetcher.cancelPrefetching()
    }
}
