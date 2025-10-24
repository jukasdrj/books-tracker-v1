# 📚 Multi-Context Search API - Examples & Testing Guide

**Version**: 2.0.0
**Base URL**: `https://books-api-proxy.jukasdrj.workers.dev`

---

## 🎯 **Quick Start Examples**

### **1. Author Search**

#### **Example 1: Stephen King (Large Bibliography)**
```bash
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=Stephen%20King&maxResults=10&page=0" | jq '{
  searchContext: .searchContext,
  provider: .provider,
  totalItems: .totalItems,
  cached: .cached,
  responseTime: .responseTime,
  pagination: .pagination,
  firstThreeBooks: .items[0:3] | map({title: .volumeInfo.title, authors: .volumeInfo.authors})
}'
```

**Expected Response**:
```json
{
  "searchContext": "author",
  "provider": "orchestrated:openlibrary+isbndb",
  "totalItems": 589,
  "cached": false,
  "responseTime": 1234,
  "pagination": {
    "page": 0,
    "maxResults": 10,
    "totalPages": 59
  },
  "firstThreeBooks": [
    {
      "title": "The Shining",
      "authors": ["Stephen King"]
    },
    {
      "title": "It",
      "authors": ["Stephen King"]
    },
    {
      "title": "Carrie",
      "authors": ["Stephen King"]
    }
  ]
}
```

#### **Example 2: J.K. Rowling (Moderate Bibliography)**
```bash
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=J.K.%20Rowling&maxResults=20" | jq '{
  totalItems: .totalItems,
  provider: .provider,
  harryPotterBooks: .items | map(select(.volumeInfo.title | contains("Harry Potter"))) | length
}'
```

**Expected Response**:
```json
{
  "totalItems": 47,
  "provider": "orchestrated:openlibrary+isbndb",
  "harryPotterBooks": 7
}
```

#### **Example 3: Unknown Author (Fallback to Google Books)**
```bash
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=Nonexistent%20Author12345" | jq '{
  totalItems: .totalItems,
  provider: .provider,
  error: .error
}'
```

**Expected Response** (if OpenLibrary fails):
```json
{
  "totalItems": 0,
  "provider": "fallback:google-books",
  "error": "No author results found for \"Nonexistent Author12345\" from any provider"
}
```

---

### **2. Title Search**

#### **Example 1: Exact Title Match**
```bash
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/title?q=The%20Martian&maxResults=10" | jq '{
  searchContext: .searchContext,
  provider: .provider,
  totalItems: .totalItems,
  firstResult: .items[0] | {
    title: .volumeInfo.title,
    authors: .volumeInfo.authors,
    publishedDate: .volumeInfo.publishedDate,
    pageCount: .volumeInfo.pageCount
  }
}'
```

**Expected Response**:
```json
{
  "searchContext": "title",
  "provider": "orchestrated:google-books+openlibrary",
  "totalItems": 15,
  "firstResult": {
    "title": "The Martian",
    "authors": ["Andy Weir"],
    "publishedDate": "2014",
    "pageCount": 369
  }
}
```

#### **Example 2: Partial Title Match**
```bash
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/title?q=Harry%20Potter%20Philosopher&maxResults=5" | jq '{
  totalItems: .totalItems,
  titles: .items | map(.volumeInfo.title)
}'
```

**Expected Response**:
```json
{
  "totalItems": 8,
  "titles": [
    "Harry Potter and the Philosopher's Stone",
    "Harry Potter and the Sorcerer's Stone",
    "Harry Potter and the Philosopher's Stone: Illustrated Edition",
    "Harry Potter and the Philosopher's Stone: MinaLima Edition",
    "Harry Potter and the Philosopher's Stone: Gryffindor Edition"
  ]
}
```

#### **Example 3: Title with Special Characters**
```bash
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/title?q=The%20Hitchhiker%27s%20Guide%20to%20the%20Galaxy" | jq '{
  totalItems: .totalItems,
  provider: .provider
}'
```

**Expected Response**:
```json
{
  "totalItems": 12,
  "provider": "orchestrated:google-books+openlibrary"
}
```

---

### **3. Subject/Genre Search**

#### **Example 1: Science Fiction**
```bash
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/subject?q=science%20fiction&maxResults=10" | jq '{
  searchContext: .searchContext,
  provider: .provider,
  totalItems: .totalItems,
  sampleBooks: .items[0:3] | map({
    title: .volumeInfo.title,
    authors: .volumeInfo.authors,
    categories: .volumeInfo.categories
  })
}'
```

**Expected Response**:
```json
{
  "searchContext": "subject",
  "provider": "orchestrated:openlibrary-subjects+google-books-categories",
  "totalItems": 142,
  "sampleBooks": [
    {
      "title": "Dune",
      "authors": ["Frank Herbert"],
      "categories": ["Fiction", "Science Fiction"]
    },
    {
      "title": "Foundation",
      "authors": ["Isaac Asimov"],
      "categories": ["Science Fiction", "Space Opera"]
    },
    {
      "title": "Neuromancer",
      "authors": ["William Gibson"],
      "categories": ["Science Fiction", "Cyberpunk"]
    }
  ]
}
```

#### **Example 2: Biography**
```bash
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/subject?q=biography&maxResults=10&page=1" | jq '{
  totalItems: .totalItems,
  pagination: .pagination,
  currentPageTitles: .items | map(.volumeInfo.title)
}'
```

**Expected Response**:
```json
{
  "totalItems": 87,
  "pagination": {
    "page": 1,
    "maxResults": 10,
    "totalPages": 9
  },
  "currentPageTitles": [
    "Steve Jobs",
    "Becoming",
    "The Diary of a Young Girl",
    "Educated",
    "Long Walk to Freedom",
    "I Am Malala",
    "The Glass Castle",
    "Born a Crime",
    "When Breath Becomes Air",
    "Hillbilly Elegy"
  ]
}
```

#### **Example 3: Niche Subject**
```bash
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/subject?q=quantum%20physics&maxResults=5" | jq '{
  totalItems: .totalItems,
  provider: .provider
}'
```

**Expected Response**:
```json
{
  "totalItems": 34,
  "provider": "orchestrated:openlibrary-subjects+google-books-categories"
}
```

---

## 🔍 **Cache Behavior Examples**

### **First Request (Cache MISS)**
```bash
curl -si "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=Neil%20Gaiman&maxResults=10" | grep -E "X-Cache:|X-Provider:|X-Response-Time:"
```

**Expected Headers**:
```
X-Cache: MISS
X-Provider: orchestrated:openlibrary+isbndb
X-Response-Time: 1234ms
X-Search-Context: author
```

### **Second Request (Cache HIT)**
```bash
curl -si "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=Neil%20Gaiman&maxResults=10" | grep -E "X-Cache:|X-Provider:|X-Response-Time:"
```

**Expected Headers**:
```
X-Cache: HIT
X-Provider: orchestrated:openlibrary+isbndb
X-Response-Time: 23ms
X-Search-Context: author
```

**Cache Age Verification**:
```bash
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=Neil%20Gaiman&maxResults=10" | jq '{
  cached: .cached,
  cacheAge: .cacheAge,
  timestamp: .timestamp
}'
```

---

## 📄 **Pagination Examples**

### **Page 0 (First 20 Results)**
```bash
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=Agatha%20Christie&maxResults=20&page=0" | jq '{
  totalItems: .totalItems,
  pagination: .pagination,
  itemsReturned: .items | length
}'
```

**Expected Response**:
```json
{
  "totalItems": 245,
  "pagination": {
    "page": 0,
    "maxResults": 20,
    "totalPages": 13
  },
  "itemsReturned": 20
}
```

### **Page 5 (Results 100-120)**
```bash
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=Agatha%20Christie&maxResults=20&page=5" | jq '{
  pagination: .pagination,
  itemsReturned: .items | length
}'
```

**Expected Response**:
```json
{
  "pagination": {
    "page": 5,
    "maxResults": 20,
    "totalPages": 13
  },
  "itemsReturned": 20
}
```

### **Last Page (Partial Results)**
```bash
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=Agatha%20Christie&maxResults=20&page=12" | jq '{
  pagination: .pagination,
  itemsReturned: .items | length
}'
```

**Expected Response**:
```json
{
  "pagination": {
    "page": 12,
    "maxResults": 20,
    "totalPages": 13
  },
  "itemsReturned": 5
}
```

---

## ⚠️ **Error Handling Examples**

### **Missing Query Parameter**
```bash
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/author" | jq
```

**Expected Response** (400 Bad Request):
```json
{
  "error": "Query parameter 'q' required",
  "searchContext": "author"
}
```

### **Provider Failure (Graceful Degradation)**
```bash
# Simulated: OpenLibrary is down, falls back to Google Books
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=Margaret%20Atwood" | jq '{
  provider: .provider,
  fallbackReason: .fallbackReason,
  totalItems: .totalItems
}'
```

**Expected Response**:
```json
{
  "provider": "fallback:google-books",
  "fallbackReason": "OpenLibrary unavailable",
  "totalItems": 42
}
```

### **No Results Found**
```bash
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/title?q=asdfjkl123impossible" | jq '{
  totalItems: .totalItems,
  items: .items,
  error: .error
}'
```

**Expected Response**:
```json
{
  "totalItems": 0,
  "items": [],
  "error": "No title results found for \"asdfjkl123impossible\""
}
```

---

## 🧪 **Testing Scenarios**

### **1. Load Testing (Apache Bench)**
```bash
# Test author search under load
ab -n 1000 -c 10 "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=Stephen%20King&maxResults=10"
```

**Expected Results**:
- First 10 requests: ~1200ms average (cache miss)
- Remaining 990 requests: ~30ms average (cache hit)
- 0% failed requests
- 95th percentile: <100ms

### **2. Cache Effectiveness Test**
```bash
# Clear cache (wait for TTL expiry or deploy)
# Then run:
for i in {1..10}; do
  echo "Request $i:"
  curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=Neil%20Gaiman&maxResults=10" | jq -r '.responseTime, .cached'
  sleep 1
done
```

**Expected Output**:
```
Request 1:
1234
false
Request 2:
23
true
Request 3:
23
true
...
Request 10:
23
true
```

### **3. Pagination Consistency Test**
```bash
# Fetch all pages and verify no duplicates
for page in {0..5}; do
  curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=Stephen%20King&maxResults=20&page=$page" \
    | jq '.items[].volumeInfo.title' >> all_titles.txt
done

# Check for duplicates
sort all_titles.txt | uniq -d
```

**Expected Output**: (empty - no duplicates)

---

## 📊 **Performance Benchmarks**

### **Target Response Times**:

| Scenario | Target | Acceptable | Poor |
|----------|--------|------------|------|
| **Cache HIT** | <50ms | <100ms | >200ms |
| **Cache MISS (Single Provider)** | <1s | <2s | >3s |
| **Cache MISS (Parallel Providers)** | <1.5s | <3s | >5s |
| **Fallback Activation** | <2s | <4s | >6s |

### **Benchmark Commands**:
```bash
# Measure response time for each context
for context in author title subject; do
  echo "Testing $context search:"
  curl -o /dev/null -s -w "Time: %{time_total}s\n" \
    "https://books-api-proxy.jukasdrj.workers.dev/search/$context?q=test&maxResults=10"
done
```

---

## 🔧 **Debugging Examples**

### **1. Real-Time Log Monitoring**
```bash
# Monitor all author searches
wrangler tail books-api-proxy --search "Author search" --format pretty

# Monitor cache performance
wrangler tail books-api-proxy --search "Cache" --format pretty

# Monitor provider fallbacks
wrangler tail books-api-proxy --search "Falling back" --format pretty
```

### **2. Provider Performance Analysis**
```bash
# Check which providers are responding
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/title?q=The%20Martian" | jq '{
  provider: .provider,
  responseTime: .responseTime,
  totalItems: .totalItems
}'
```

### **3. Cache Key Debugging**
```bash
# Verify cache keys are being generated correctly
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=Test%20Author&maxResults=10&page=0" \
  | jq '{cached: .cached, timestamp: .timestamp}'

# Same query should hit cache
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=Test%20Author&maxResults=10&page=0" \
  | jq '{cached: .cached, cacheAge: .cacheAge}'
```

---

## 🎯 **iOS App Integration Examples**

### **SwiftUI SearchModel Integration**

```swift
// SearchModel.swift
enum SearchContext: String {
    case all = "auto"      // Legacy general search
    case author = "author" // NEW: Dedicated author search
    case title = "title"   // NEW: Dedicated title search
    case isbn = "title"    // ISBN is a type of title search
}

func performSearch(query: String, context: SearchContext, page: Int = 0) async {
    let baseURL = "https://books-api-proxy.jukasdrj.workers.dev"
    let endpoint = "/search/\(context.rawValue)"
    let maxResults = 20

    guard var components = URLComponents(string: baseURL + endpoint) else { return }
    components.queryItems = [
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "maxResults", value: "\(maxResults)"),
        URLQueryItem(name: "page", value: "\(page)")
    ]

    guard let url = components.url else { return }

    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)

        // Update UI
        await MainActor.run {
            self.searchResults = response.items
            self.totalItems = response.totalItems
            self.currentPage = page
            self.totalPages = response.pagination?.totalPages ?? 1
            self.cached = response.cached
            self.responseTime = response.responseTime
        }
    } catch {
        print("Search failed: \(error)")
    }
}
```

### **Pagination Example**

```swift
// LoadMoreView.swift
struct LoadMoreButton: View {
    @ObservedObject var searchModel: SearchModel

    var body: some View {
        if searchModel.hasMorePages {
            Button("Load More Results") {
                Task {
                    await searchModel.loadNextPage()
                }
            }
            .disabled(searchModel.isLoadingMore)
        }
    }
}

// SearchModel extension
extension SearchModel {
    var hasMorePages: Bool {
        currentPage < (totalPages - 1)
    }

    func loadNextPage() async {
        guard hasMorePages else { return }
        isLoadingMore = true
        await performSearch(query: lastQuery, context: lastContext, page: currentPage + 1)
        isLoadingMore = false
    }
}
```

---

## 📋 **Quick Reference Card**

### **Endpoints**:
| Endpoint | Purpose | Cache TTL | Provider Strategy |
|----------|---------|-----------|-------------------|
| `/search/author?q={name}` | Author bibliography | 24h | OpenLibrary → ISBNdb → Google (fallback) |
| `/search/title?q={title}` | Title search | 6h | Google + OpenLibrary (parallel) |
| `/search/subject?q={genre}` | Genre/subject discovery | 12h | OpenLibrary + Google (parallel) |
| `/search/auto?q={query}` | Legacy general search | 1h | Smart detection (DEPRECATED) |

### **Parameters**:
| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `q` | ✅ Yes | - | Search query |
| `maxResults` | ❌ No | 20 | Results per page |
| `page` | ❌ No | 0 | Page number (0-indexed) |

### **Response Headers**:
| Header | Example | Description |
|--------|---------|-------------|
| `X-Cache` | `HIT` or `MISS` | Cache status |
| `X-Provider` | `orchestrated:openlibrary+isbndb` | Provider used |
| `X-Search-Context` | `author` | Search context |
| `X-Response-Time` | `1234ms` | Response time in milliseconds |

---

**Last Updated**: September 30, 2025
**Status**: ✅ Ready for Testing
**Version**: 2.0.0
