import Testing
import SwiftUI
@testable import BooksTrackerFeature

@Suite("FlowLayout Tests")
struct FlowLayoutTests {
    
    // MARK: - Mock Subview for Testing
    
    /// Mock subview that implements LayoutSubview protocol for testing
    private struct MockSubview: LayoutSubview {
        let size: CGSize
        var priority: Double = 0
        
        func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
            return size
        }
        
        func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
            // No-op for testing
        }
        
        subscript<K>(key: K.Type) -> K.Value where K : LayoutValueKey {
            return key.defaultValue
        }
    }
    
    // MARK: - Helper Methods
    
    private func createMockSubviews(sizes: [CGSize]) -> [MockSubview] {
        return sizes.map { MockSubview(size: $0) }
    }
    
    // MARK: - Basic Layout Tests
    
    @Test("FlowLayout with default spacing")
    func testDefaultSpacing() {
        // Given
        let layout = FlowLayout()
        
        // Then
        #expect(layout.spacing == 8.0)
    }
    
    @Test("FlowLayout with custom spacing")
    func testCustomSpacing() {
        // Given
        let customSpacing: CGFloat = 12.0
        let layout = FlowLayout(spacing: customSpacing)
        
        // Then
        #expect(layout.spacing == customSpacing)
    }
    
    // MARK: - Size Calculation Tests
    
    @Test("Single item fits in container width")
    func testSingleItemLayout() {
        // Given
        let layout = FlowLayout(spacing: 8)
        let subviews = createMockSubviews(sizes: [CGSize(width: 100, height: 30)])
        let proposal = ProposedViewSize(width: 200, height: nil)
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        #expect(result.width == 200) // Uses full proposed width
        #expect(result.height == 30) // Height of single item
    }
    
    @Test("Multiple items on single line")
    func testMultipleItemsSingleLine() {
        // Given
        let layout = FlowLayout(spacing: 8)
        let subviews = createMockSubviews(sizes: [
            CGSize(width: 50, height: 30),
            CGSize(width: 60, height: 25),
            CGSize(width: 40, height: 35)
        ])
        let proposal = ProposedViewSize(width: 200, height: nil)
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        // Total width: 50 + 8 + 60 + 8 + 40 = 166 (fits in 200)
        #expect(result.width == 200) // Uses full proposed width
        #expect(result.height == 35) // Height of tallest item
    }
    
    @Test("Items wrap to multiple lines")
    func testItemsWrapToMultipleLines() {
        // Given
        let layout = FlowLayout(spacing: 8)
        let subviews = createMockSubviews(sizes: [
            CGSize(width: 80, height: 30),
            CGSize(width: 90, height: 25),
            CGSize(width: 70, height: 35) // This should wrap to next line
        ])
        let proposal = ProposedViewSize(width: 180, height: nil)
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        // First line: 80 + 8 + 90 = 178 (fits in 180)
        // Second line: 70
        // Total height: max(30, 25) + 8 + 35 = 73
        #expect(result.width == 180) // Uses full proposed width
        #expect(result.height == 73) // Two lines with spacing
    }
    
    @Test("Empty subviews returns zero size")
    func testEmptySubviews() {
        // Given
        let layout = FlowLayout(spacing: 8)
        let subviews: [MockSubview] = []
        let proposal = ProposedViewSize(width: 200, height: nil)
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        #expect(result.width == 200) // Uses proposed width
        #expect(result.height == 0) // No items, no height
    }
    
    @Test("Single item larger than container width")
    func testSingleItemLargerThanContainer() {
        // Given
        let layout = FlowLayout(spacing: 8)
        let subviews = createMockSubviews(sizes: [CGSize(width: 250, height: 30)])
        let proposal = ProposedViewSize(width: 200, height: nil)
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        #expect(result.width == 200) // Uses proposed width
        #expect(result.height == 30) // Height of single item
    }
    
    // MARK: - Edge Cases
    
    @Test("Zero spacing between items")
    func testZeroSpacing() {
        // Given
        let layout = FlowLayout(spacing: 0)
        let subviews = createMockSubviews(sizes: [
            CGSize(width: 50, height: 30),
            CGSize(width: 60, height: 25)
        ])
        let proposal = ProposedViewSize(width: 200, height: nil)
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        // Total width: 50 + 0 + 60 = 110 (fits in 200)
        #expect(result.width == 200) // Uses full proposed width
        #expect(result.height == 30) // Height of tallest item
    }
    
    @Test("Negative spacing between items")
    func testNegativeSpacing() {
        // Given
        let layout = FlowLayout(spacing: -5)
        let subviews = createMockSubviews(sizes: [
            CGSize(width: 50, height: 30),
            CGSize(width: 60, height: 25)
        ])
        let proposal = ProposedViewSize(width: 200, height: nil)
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        // Total width: 50 + (-5) + 60 = 105 (fits in 200)
        #expect(result.width == 200) // Uses full proposed width
        #expect(result.height == 30) // Height of tallest item
    }
    
    @Test("Items with zero width")
    func testItemsWithZeroWidth() {
        // Given
        let layout = FlowLayout(spacing: 8)
        let subviews = createMockSubviews(sizes: [
            CGSize(width: 0, height: 30),
            CGSize(width: 50, height: 25),
            CGSize(width: 0, height: 35)
        ])
        let proposal = ProposedViewSize(width: 200, height: nil)
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        // Total width: 0 + 8 + 50 + 8 + 0 = 66 (fits in 200)
        #expect(result.width == 200) // Uses full proposed width
        #expect(result.height == 35) // Height of tallest item
    }
    
    @Test("Items with zero height")
    func testItemsWithZeroHeight() {
        // Given
        let layout = FlowLayout(spacing: 8)
        let subviews = createMockSubviews(sizes: [
            CGSize(width: 50, height: 0),
            CGSize(width: 60, height: 25),
            CGSize(width: 40, height: 0)
        ])
        let proposal = ProposedViewSize(width: 200, height: nil)
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        #expect(result.width == 200) // Uses full proposed width
        #expect(result.height == 25) // Height of tallest item
    }
    
    // MARK: - Container Width Edge Cases
    
    @Test("Very narrow container forces all items to wrap")
    func testVeryNarrowContainer() {
        // Given
        let layout = FlowLayout(spacing: 8)
        let subviews = createMockSubviews(sizes: [
            CGSize(width: 50, height: 30),
            CGSize(width: 60, height: 25),
            CGSize(width: 40, height: 35)
        ])
        let proposal = ProposedViewSize(width: 45, height: nil) // Narrower than any item
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        // Each item goes on its own line
        // Total height: 30 + 8 + 25 + 8 + 35 = 106
        #expect(result.width == 45) // Uses proposed width
        #expect(result.height == 106) // Three lines with spacing
    }
    
    @Test("Infinite width container puts all items on one line")
    func testInfiniteWidthContainer() {
        // Given
        let layout = FlowLayout(spacing: 8)
        let subviews = createMockSubviews(sizes: [
            CGSize(width: 50, height: 30),
            CGSize(width: 60, height: 25),
            CGSize(width: 40, height: 35)
        ])
        let proposal = ProposedViewSize(width: .infinity, height: nil)
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        #expect(result.width == .infinity) // Uses infinite width
        #expect(result.height == 35) // Height of tallest item (single line)
    }
    
    @Test("Nil width proposal defaults to infinity")
    func testNilWidthProposal() {
        // Given
        let layout = FlowLayout(spacing: 8)
        let subviews = createMockSubviews(sizes: [
            CGSize(width: 50, height: 30),
            CGSize(width: 60, height: 25)
        ])
        let proposal = ProposedViewSize(width: nil, height: nil)
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        #expect(result.width == .infinity) // Defaults to infinity
        #expect(result.height == 30) // Height of tallest item (single line)
    }
    
    // MARK: - Complex Layout Scenarios
    
    @Test("Mixed item sizes with multiple wraps")
    func testMixedItemSizesMultipleWraps() {
        // Given
        let layout = FlowLayout(spacing: 10)
        let subviews = createMockSubviews(sizes: [
            CGSize(width: 80, height: 20),  // Line 1
            CGSize(width: 90, height: 30),  // Line 1
            CGSize(width: 100, height: 25), // Line 2 (wraps)
            CGSize(width: 60, height: 35),  // Line 2
            CGSize(width: 120, height: 15), // Line 3 (wraps)
        ])
        let proposal = ProposedViewSize(width: 200, height: nil)
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        // Line 1: 80 + 10 + 90 = 180 (fits), height = max(20, 30) = 30
        // Line 2: 100 + 10 + 60 = 170 (fits), height = max(25, 35) = 35
        // Line 3: 120 (fits), height = 15
        // Total height: 30 + 10 + 35 + 10 + 15 = 100
        #expect(result.width == 200)
        #expect(result.height == 100)
    }
    
    @Test("All items same size in grid-like layout")
    func testUniformItemSizes() {
        // Given
        let layout = FlowLayout(spacing: 5)
        let itemSize = CGSize(width: 40, height: 40)
        let subviews = createMockSubviews(sizes: Array(repeating: itemSize, count: 6))
        let proposal = ProposedViewSize(width: 135, height: nil) // Fits 3 items per line
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        // Line 1: 40 + 5 + 40 + 5 + 40 = 130 (fits 3 items)
        // Line 2: 40 + 5 + 40 + 5 + 40 = 130 (fits 3 items)
        // Total height: 40 + 5 + 40 = 85
        #expect(result.width == 135)
        #expect(result.height == 85)
    }
    
    // MARK: - Performance and Stress Tests
    
    @Test("Large number of items")
    func testLargeNumberOfItems() {
        // Given
        let layout = FlowLayout(spacing: 2)
        let itemSize = CGSize(width: 20, height: 20)
        let subviews = createMockSubviews(sizes: Array(repeating: itemSize, count: 100))
        let proposal = ProposedViewSize(width: 200, height: nil)
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        // Each line fits: (200 - 2*8) / (20 + 2) ≈ 8 items (with spacing)
        // 100 items / 8 per line ≈ 13 lines (rounded up)
        // Height should be reasonable for 100 items
        #expect(result.width == 200)
        #expect(result.height > 0)
        #expect(result.height < 1000) // Sanity check - shouldn't be too tall
    }
    
    // MARK: - Real-world Scenarios
    
    @Test("Tag-like layout scenario")
    func testTagLikeLayout() {
        // Given - Simulating text tags of varying lengths
        let layout = FlowLayout(spacing: 8)
        let subviews = createMockSubviews(sizes: [
            CGSize(width: 45, height: 24),  // "Swift"
            CGSize(width: 65, height: 24),  // "SwiftUI"
            CGSize(width: 35, height: 24),  // "iOS"
            CGSize(width: 55, height: 24),  // "Testing"
            CGSize(width: 75, height: 24),  // "Development"
            CGSize(width: 40, height: 24),  // "Code"
        ])
        let proposal = ProposedViewSize(width: 180, height: nil)
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        // Should wrap appropriately for tag-like display
        #expect(result.width == 180)
        #expect(result.height >= 24) // At least one line
        #expect(result.height <= 100) // Reasonable for 6 tags
    }
    
    @Test("Button layout scenario")
    func testButtonLayoutScenario() {
        // Given - Simulating action buttons
        let layout = FlowLayout(spacing: 12)
        let subviews = createMockSubviews(sizes: [
            CGSize(width: 80, height: 44),  // "Cancel"
            CGSize(width: 60, height: 44),  // "Save"
            CGSize(width: 70, height: 44),  // "Delete"
        ])
        let proposal = ProposedViewSize(width: 250, height: nil)
        
        // When
        let result = layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &())
        
        // Then
        // All buttons should fit on one line: 80 + 12 + 60 + 12 + 70 = 234
        #expect(result.width == 250)
        #expect(result.height == 44) // Single line of buttons
    }
}