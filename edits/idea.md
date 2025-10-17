idea.md

This is a common and predictable failure mode for large-scale data imports, and the good news is that the errors are **not due to timeouts**.

The enrichment failures you are experiencing are almost certainly caused by **overly specific or imperfect search query data** extracted from your CSV, which leads to the search providers returning zero relevant results.

Here is a breakdown of why this is happening and what the code is doing:

### 1. The Cause: Overly Specific Search Data

The console output clearly shows that the Cloudflare Worker successfully responded, often very quickly (`"responseTime":619ms`), but returned **zero results** (`"totalItems":0,"items":[]`).

* **Evidence against Timeout:** The specific failure message is `noMatchFound`, not a timeout (`apiError(Timeout Error)` or `httpError(504)`). This confirms the search successfully completed, but the result set was empty or contained only irrelevant data.
* **Evidence for Bad Data:** The failing titles are highly specific and often include metadata like series names or sub-titles from the CSV source:
    * `The da Vinci Code: The Young Adult Adaptation`
    * `Devil's Knot: The True Story of the West Memphis Three (Justice Knot, #1)`

When the `EnrichmentService` constructs the search query using the title and author, passing the full, specific title string (e.g., `The da Vinci Code: The Young Adult Adaptation`) to a search API often results in zero matches, as the primary work's title is just `"The da Vinci Code"`.

---

### 2. The Mechanism: Conservative Matching Logic

The system is failing safely, choosing not to enrich rather than risking a match with the wrong book.

1.  **Backend Returns Zero:** For titles like `"The da Vinci Code: The Young Adult Adaptation"`, the underlying search providers (Google Books/OpenLibrary) likely return `{ "totalItems": 0 }`,..."}].
2.  **`findBestMatch` Fails:** Even if the search API returned a few irrelevant items, the internal scoring logic, implemented in `EnrichmentService.swift` within `findBestMatch`, would assign a low score (below 50).
3.  **Safe Exit:** Because no acceptable match was found, the `enrichWork` function throws the specific error you see: `.noMatchFound`.

### 3. Proposed Solution

To fix these sporadic failures, the solution lies in **improving the title normalization** before the search.

The best long-term fix would involve editing your CSV import file or the parser logic (`CSVParsingActor.swift`) to strip common patterns that interfere with generic book searches.

| Problematic Title | Stripped Title (Better Search) |
| :--- | :--- |
| `The da Vinci Code: The Young Adult Adaptation` | **`The da Vinci Code`** |
| `Devil's Knot: The True Story of the West Memphis Three (Justice Knot, #1)` | **`Devil's Knot`** |
| `Dept. of Speculation` | **`Dept of Speculation`** |

This will ensure the search query sent to the powerful `/search/advanced` endpoint is clean enough to find the book's main entry in the database.