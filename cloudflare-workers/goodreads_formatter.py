#!/usr/bin/env python3
"""
🚀 Goodreads to Cache Warmer Formatter
Converts Goodreads CSV export to author list for cache warming system
"""

import csv
import json
import re
from collections import defaultdict

def clean_author_name(author_name):
    """Clean and normalize author names"""
    if not author_name:
        return None

    # Remove quotes and extra whitespace
    author_name = author_name.strip().strip('"').strip()

    # Skip empty names
    if not author_name:
        return None

    # Skip generic entries
    skip_patterns = [
        r'^various$',
        r'^unknown$',
        r'^anonymous$',
        r'^editor$',
        r'^translator$'
    ]

    for pattern in skip_patterns:
        if re.match(pattern, author_name, re.IGNORECASE):
            return None

    return author_name

def extract_authors_from_goodreads(csv_file_path):
    """Extract unique authors from Goodreads CSV export"""
    authors = defaultdict(lambda: {"books": [], "total_books": 0})

    print(f"📚 Processing Goodreads export: {csv_file_path}")

    with open(csv_file_path, 'r', encoding='utf-8') as file:
        reader = csv.DictReader(file)

        for row_num, row in enumerate(reader, 1):
            title = row.get('Title', '').strip()
            author = clean_author_name(row.get('Author', ''))
            additional_authors = row.get('Additional Authors', '').strip()

            # Process main author
            if author:
                authors[author]["books"].append({
                    "title": title,
                    "isbn": row.get('ISBN13', '').strip().strip('"').strip('='),
                    "rating": row.get('My Rating', '0'),
                    "shelf": row.get('Exclusive Shelf', 'unknown')
                })
                authors[author]["total_books"] += 1

            # Process additional authors
            if additional_authors:
                # Split by comma and clean each name
                additional_list = [clean_author_name(name) for name in additional_authors.split(',')]
                for additional_author in additional_list:
                    if additional_author:
                        authors[additional_author]["books"].append({
                            "title": title,
                            "isbn": row.get('ISBN13', '').strip().strip('"').strip('='),
                            "rating": row.get('My Rating', '0'),
                            "shelf": row.get('Exclusive Shelf', 'unknown'),
                            "role": "additional_author"
                        })
                        authors[additional_author]["total_books"] += 1

    print(f"✅ Processed {row_num} books")
    print(f"🎯 Found {len(authors)} unique authors")

    return authors

def create_cache_warming_format(authors_data):
    """Create the format expected by cache warming system"""

    # Sort authors by total books (most prolific first)
    sorted_authors = sorted(
        authors_data.items(),
        key=lambda x: x[1]["total_books"],
        reverse=True
    )

    # Create the cache warming format
    cache_format = {
        "metadata": {
            "source": "goodreads_export",
            "total_authors": len(sorted_authors),
            "total_books": sum(data["total_books"] for _, data in sorted_authors),
            "export_date": "2025-09-27",
            "format_version": "1.0"
        },
        "authors": []
    }

    # Add authors data
    for author_name, author_data in sorted_authors:
        cache_format["authors"].append({
            "name": author_name,
            "book_count": author_data["total_books"],
            "books": author_data["books"][:10]  # Limit to first 10 books for cache warming
        })

    return cache_format

def create_simple_author_list(authors_data):
    """Create a simple list of author names for cache warming"""
    # Sort by book count and get just the names
    sorted_authors = sorted(
        authors_data.items(),
        key=lambda x: x[1]["total_books"],
        reverse=True
    )

    return [author_name for author_name, _ in sorted_authors]

def main():
    """Main processing function"""
    csv_path = "/Users/justingardner/Library/Mobile Documents/com~apple~CloudDocs/goodreads_library_export.csv"

    print("🎯 BooksTracker Cache Warming Formatter")
    print("=" * 50)

    # Extract authors from Goodreads CSV
    authors_data = extract_authors_from_goodreads(csv_path)

    # Create cache warming format
    cache_format = create_cache_warming_format(authors_data)

    # Create simple author list
    author_names = create_simple_author_list(authors_data)

    # Write detailed JSON format
    detailed_output = "/Users/justingardner/Downloads/xcode/books_tracker_v1/cloudflare-workers/goodreads_authors_detailed.json"
    with open(detailed_output, 'w', encoding='utf-8') as f:
        json.dump(cache_format, f, indent=2, ensure_ascii=False)

    # Write simple author list
    simple_output = "/Users/justingardner/Downloads/xcode/books_tracker_v1/cloudflare-workers/goodreads_authors_simple.json"
    with open(simple_output, 'w', encoding='utf-8') as f:
        json.dump(author_names, f, indent=2, ensure_ascii=False)

    # Create CSV format for cache warmer upload
    csv_output = "/Users/justingardner/Downloads/xcode/books_tracker_v1/cloudflare-workers/goodreads_authors_for_cache.csv"
    with open(csv_output, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['author', 'book_count'])  # Header
        for author_name, author_data in sorted(authors_data.items(), key=lambda x: x[1]["total_books"], reverse=True):
            writer.writerow([author_name, author_data["total_books"]])

    print("\n🎉 SUCCESS! Generated files:")
    print(f"📄 Detailed JSON: {detailed_output}")
    print(f"📄 Simple Author List: {simple_output}")
    print(f"📄 CSV for Cache Upload: {csv_output}")

    print(f"\n📊 STATISTICS:")
    print(f"   📚 Total Books: {cache_format['metadata']['total_books']}")
    print(f"   👥 Total Authors: {cache_format['metadata']['total_authors']}")

    # Show top 10 authors
    print(f"\n🏆 TOP 10 AUTHORS BY BOOK COUNT:")
    for i, (author_name, author_data) in enumerate(sorted(authors_data.items(), key=lambda x: x[1]["total_books"], reverse=True)[:10], 1):
        print(f"   {i:2d}. {author_name} ({author_data['total_books']} books)")

    print(f"\n🚀 Ready for cache warming system upload!")
    print(f"Use: curl -X POST https://personal-library-cache-warmer.jukasdrj.workers.dev/upload-csv")

if __name__ == "__main__":
    main()