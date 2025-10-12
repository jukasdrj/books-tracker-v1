const USER_AGENT = 'BooksTracker/1.0 (nerd@ooheynerds.com) GoogleBooksWorker/1.0.0';

export async function searchGoogleBooks(query, params = {}, env) {
    const startTime = Date.now();
    try {
      console.log(`RPC: GoogleBooks search for "${query}"`);

      const apiKey = await env.GOOGLE_BOOKS_API_KEY.get();
      if (!apiKey) {
        return { success: false, error: "Google Books API key not configured." };
      }

      const maxResults = params.maxResults || 20;
      const searchUrl = `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(query)}&maxResults=${maxResults}&key=${apiKey}`;

      const response = await fetch(searchUrl, {
        headers: {
          'User-Agent': USER_AGENT,
          'Accept': 'application/json',
        },
      });

      if (!response.ok) {
        throw new Error(`Google Books API error: ${response.status} ${response.statusText}`);
      }

      const data = await response.json();
      const normalizedData = normalizeGoogleBooksResponse(data);

      const processingTime = Date.now() - startTime;

      if (env.GOOGLE_BOOKS_ANALYTICS) {
        env.GOOGLE_BOOKS_ANALYTICS.writeDataPoint({
          blobs: [query, 'search'],
          doubles: [processingTime, normalizedData.works.length],
          indexes: ['google-books-search']
        });
      }

      return {
        success: true,
        provider: 'google-books',
        processingTime,
        ...normalizedData,
      };
    } catch (error) {
      const processingTime = Date.now() - startTime;
      console.error(`RPC Error in GoogleBooksWorker.search:`, error);

      if (env.GOOGLE_BOOKS_ANALYTICS) {
        env.GOOGLE_BOOKS_ANALYTICS.writeDataPoint({
          blobs: [query, 'search_error'],
          doubles: [processingTime, 0],
          indexes: ['google-books-error']
        });
      }

      return { success: false, error: error.message, processingTime };
    }
}

export async function searchGoogleBooksByISBN(isbn, env) {
    const startTime = Date.now();
    try {
      console.log(`RPC: GoogleBooks ISBN search for "${isbn}"`);

      const apiKey = await env.GOOGLE_BOOKS_API_KEY.get();
      if (!apiKey) {
        return { success: false, error: "Google Books API key not configured." };
      }

      const searchUrl = `https://www.googleapis.com/books/v1/volumes?q=isbn:${encodeURIComponent(isbn)}&key=${apiKey}`;

      const response = await fetch(searchUrl, {
        headers: {
          'User-Agent': USER_AGENT,
          'Accept': 'application/json',
        },
      });

      if (!response.ok) {
        throw new Error(`Google Books API error: ${response.status} ${response.statusText}`);
      }

      const data = await response.json();
      const normalizedData = normalizeGoogleBooksResponse(data);

      const processingTime = Date.now() - startTime;

      if (env.GOOGLE_BOOKS_ANALYTICS) {
        env.GOOGLE_BOOKS_ANALYTICS.writeDataPoint({
          blobs: [isbn, 'isbn_search'],
          doubles: [processingTime, normalizedData.works.length],
          indexes: ['google-books-isbn']
        });
      }

      return {
        success: true,
        provider: 'google-books',
        processingTime,
        ...normalizedData,
      };
    } catch (error) {
      const processingTime = Date.now() - startTime;
      console.error(`RPC Error in GoogleBooksWorker.searchByISBN:`, error);

      if (env.GOOGLE_BOOKS_ANALYTICS) {
        env.GOOGLE_BOOKS_ANALYTICS.writeDataPoint({
          blobs: [isbn, 'isbn_search_error'],
          doubles: [processingTime, 0],
          indexes: ['google-books-error']
        });
      }

      return { success: false, error: error.message, processingTime };
    }
}

function normalizeGoogleBooksResponse(apiResponse) {
  if (!apiResponse.items || apiResponse.items.length === 0) {
    return { works: [], authors: [] };
  }

  const worksMap = new Map();
  const authorsMap = new Map();

  apiResponse.items.forEach(item => {
    const volumeInfo = item.volumeInfo;
    if (!volumeInfo || !volumeInfo.title) {
      return;
    }

    const authors = volumeInfo.authors || ['Unknown Author'];

    const workKey = `${volumeInfo.title.toLowerCase()}-${authors[0].toLowerCase()}`;

    if (!worksMap.has(workKey)) {
      worksMap.set(workKey, {
        title: volumeInfo.title,
        subtitle: volumeInfo.subtitle,
        authors: authors.map(name => ({ name })),
        editions: [],
        firstPublishYear: extractYear(volumeInfo.publishedDate),
        firstPublicationYear: extractYear(volumeInfo.publishedDate),
      });
    }

    const work = worksMap.get(workKey);

    const isbn13 = volumeInfo.industryIdentifiers?.find(id => id.type === 'ISBN_13')?.identifier;
    const isbn10 = volumeInfo.industryIdentifiers?.find(id => id.type === 'ISBN_10')?.identifier;

    work.editions.push({
      googleBooksVolumeId: item.id,
      isbn13: isbn13,
      isbn10: isbn10,
      title: volumeInfo.title,
      subtitle: volumeInfo.subtitle,
      publisher: volumeInfo.publisher,
      publishDate: volumeInfo.publishedDate,
      publicationDate: volumeInfo.publishedDate,
      publishYear: extractYear(volumeInfo.publishedDate),
      pages: volumeInfo.pageCount,
      pageCount: volumeInfo.pageCount,
      language: volumeInfo.language,
      genres: volumeInfo.categories || [],
      description: volumeInfo.description,
      coverImageURL: volumeInfo.imageLinks?.thumbnail?.replace('http:', 'https:'),
      previewLink: volumeInfo.previewLink,
      infoLink: volumeInfo.infoLink,
      source: 'google-books',
    });

    authors.forEach(authorName => {
      if (!authorsMap.has(authorName)) {
        authorsMap.set(authorName, {
          name: authorName,
          source: 'google-books'
        });
      }
    });
  });

  return {
    works: Array.from(worksMap.values()),
    authors: Array.from(authorsMap.values())
  };
}

function extractYear(dateString) {
  if (!dateString) return null;
  const yearMatch = dateString.match(/(\d{4})/);
  return yearMatch ? parseInt(yearMatch[1], 10) : null;
}
