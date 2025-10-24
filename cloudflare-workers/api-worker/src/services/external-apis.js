/**
 * External API integrations (Google Books, OpenLibrary, ISBNdb)
 * Migrated from external-apis-worker
 *
 * This service provides functions for searching and enriching book data
 * from multiple external providers.
 */

// ============================================================================
// Google Books API
// ============================================================================

const GOOGLE_BOOKS_USER_AGENT = 'BooksTracker/1.0 (nerd@ooheynerds.com) GoogleBooksWorker/1.0.0';

export async function searchGoogleBooks(query, params = {}, env) {
  const startTime = Date.now();
  try {
    console.log(`GoogleBooks search for "${query}"`);

    // Handle both secrets store (has .get() method) and direct env var
    const apiKey = env.GOOGLE_BOOKS_API_KEY?.get
      ? await env.GOOGLE_BOOKS_API_KEY.get()
      : env.GOOGLE_BOOKS_API_KEY;

    if (!apiKey) {
      return { success: false, error: "Google Books API key not configured." };
    }

    const maxResults = params.maxResults || 20;
    const searchUrl = `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(query)}&maxResults=${maxResults}&key=${apiKey}`;

    const response = await fetch(searchUrl, {
      headers: {
        'User-Agent': GOOGLE_BOOKS_USER_AGENT,
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
    console.error(`Error in GoogleBooks search:`, error);

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
    console.log(`GoogleBooks ISBN search for "${isbn}"`);

    // Handle both secrets store (has .get() method) and direct env var
    const apiKey = env.GOOGLE_BOOKS_API_KEY?.get
      ? await env.GOOGLE_BOOKS_API_KEY.get()
      : env.GOOGLE_BOOKS_API_KEY;

    if (!apiKey) {
      return { success: false, error: "Google Books API key not configured." };
    }

    const searchUrl = `https://www.googleapis.com/books/v1/volumes?q=isbn:${encodeURIComponent(isbn)}&key=${apiKey}`;

    const response = await fetch(searchUrl, {
      headers: {
        'User-Agent': GOOGLE_BOOKS_USER_AGENT,
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
    console.error(`Error in GoogleBooks ISBN search:`, error);

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

// ============================================================================
// OpenLibrary API
// ============================================================================

const OPENLIBRARY_USER_AGENT = 'BooksTracker/1.0 (nerd@ooheynerds.com) OpenLibraryWorker/1.1.0';

export async function searchOpenLibrary(query, params = {}, env) {
  try {
    console.log(`OpenLibrary general search for "${query}"`);

    const maxResults = params.maxResults || 20;

    const searchUrl = `https://openlibrary.org/search.json?q=${encodeURIComponent(query)}&limit=${maxResults}`;
    const response = await fetch(searchUrl, {
      headers: { 'User-Agent': OPENLIBRARY_USER_AGENT }
    });

    if (!response.ok) {
      throw new Error(`OpenLibrary search API failed: ${response.status}`);
    }

    const data = await response.json();
    const works = normalizeOpenLibrarySearchResults(data.docs || []);

    return {
      success: true,
      provider: 'openlibrary',
      works: works,
      totalResults: data.numFound || 0
    };

  } catch (error) {
    console.error(`Error in OpenLibrary search for "${query}":`, error);
    return { success: false, error: error.message };
  }
}

export async function getOpenLibraryAuthorWorks(authorName, env) {
  try {
    console.log(`OpenLibrary getAuthorWorks("${authorName}")`);

    const authorKey = await findAuthorKeyByName(authorName);
    if (!authorKey) {
      return { success: false, error: 'Author not found in OpenLibrary' };
    }

    const works = await getWorksByAuthorKey(authorKey);

    const response = {
      success: true,
      provider: 'openlibrary',
      author: {
        name: authorName,
        openLibraryKey: authorKey,
      },
      works: works,
    };

    return response;

  } catch (error) {
    console.error(`Error in getAuthorWorks for "${authorName}":`, error);
    return { success: false, error: error.message };
  }
}

function normalizeOpenLibrarySearchResults(docs) {
  const worksMap = new Map();

  docs.forEach(doc => {
    const isWork = doc.type === 'work' || (doc.key && doc.key.startsWith('/works/'));

    if (!isWork) {
      const potentialWorkKey = doc.key?.replace('/books/', '/works/').replace(/M$/, 'W');
      if (worksMap.has(potentialWorkKey)) {
        return;
      }
    }

    const workKey = doc.key || `synthetic-${doc.title?.replace(/\s+/g, '-').toLowerCase()}`;

    if (!worksMap.has(workKey)) {
      const work = {
        title: doc.title || 'Unknown Title',
        subtitle: doc.subtitle,
        authors: (doc.author_name || []).map(name => ({ name })),
        firstPublicationYear: doc.first_publish_year,
        subjects: doc.subject || [],

        externalIds: {
          openLibraryWorkId: isWork ? extractWorkId(doc.key) : null,
          openLibraryEditionId: !isWork ? extractEditionId(doc.key) : null,
          goodreadsWorkIds: doc.id_goodreads || [],
          amazonASINs: doc.id_amazon || [],
          librarythingIds: doc.id_librarything || [],
          googleBooksVolumeIds: doc.id_google || [],
          isbndbIds: [],
        },

        editions: [{
          isbn10: doc.isbn?.[0],
          isbn13: doc.isbn?.find(isbn => isbn.length === 13),
          publisher: doc.publisher?.[0],
          publicationDate: doc.publish_date?.[0],
          pageCount: doc.number_of_pages_median,
          language: doc.language?.[0],
          coverImageURL: doc.cover_i ? `https://covers.openlibrary.org/b/id/${doc.cover_i}-L.jpg` : null,
          externalIds: {
            openLibraryEditionId: !isWork ? extractEditionId(doc.key) : null,
            googleBooksVolumeIds: doc.id_google || [],
            amazonASINs: doc.id_amazon || []
          }
        }],

        source: 'openlibrary'
      };

      worksMap.set(workKey, work);
    }
  });

  return Array.from(worksMap.values());
}

function extractWorkId(key) {
  if (!key) return null;
  const match = key.match(/\/works\/([^\/]+)/);
  return match ? match[1] : null;
}

function extractEditionId(key) {
  if (!key) return null;
  const match = key.match(/\/books\/([^\/]+)/);
  return match ? match[1] : null;
}

async function findAuthorKeyByName(authorName) {
  const searchUrl = `https://openlibrary.org/search/authors.json?q=${encodeURIComponent(authorName)}&limit=1`;
  const response = await fetch(searchUrl, { headers: { 'User-Agent': OPENLIBRARY_USER_AGENT } });
  if (!response.ok) throw new Error('OpenLibrary author search API failed');
  const data = await response.json();
  return data.docs && data.docs.length > 0 ? data.docs[0].key : null;
}

async function getWorksByAuthorKey(authorKey) {
  const worksUrl = `https://openlibrary.org/authors/${authorKey}/works.json?limit=1000`;
  const response = await fetch(worksUrl, { headers: { 'User-Agent': OPENLIBRARY_USER_AGENT } });
  if (!response.ok) throw new Error('OpenLibrary works fetch API failed');
  const data = await response.json();

  console.log(`OpenLibrary returned ${data.entries?.length || 0} works for ${authorKey}`);

  return (data.entries || []).map(work => ({
    title: work.title,
    openLibraryWorkKey: work.key,
    firstPublicationYear: work.first_publish_year,
    editions: [],
  }));
}

// ============================================================================
// ISBNdb API
// ============================================================================

const RATE_LIMIT_KEY = 'isbndb_last_request';
const RATE_LIMIT_INTERVAL = 1000;

/**
 * Search ISBNdb for books by title and author using combined search endpoint
 * This is optimized for enrichment - uses both author and text parameters
 */
export async function searchISBNdb(title, authorName, env) {
  try {
    console.log(`ISBNdb search for "${title}" by "${authorName || 'any author'}"`);

    // Build search URL with author and text parameters
    let searchUrl = `https://api2.isbndb.com/search/books?page=1&pageSize=20&text=${encodeURIComponent(title)}`;
    if (authorName) {
      searchUrl += `&author=${encodeURIComponent(authorName)}`;
    }

    await enforceRateLimit(env);
    const searchResponse = await fetchWithAuth(searchUrl, env);

    if (!searchResponse.books || searchResponse.books.length === 0) {
      return { success: true, works: [], totalResults: 0 };
    }

    // Convert ISBNdb books to normalized work format
    const works = searchResponse.books.map(book => ({
      title: book.title,
      subtitle: book.title_long !== book.title ? book.title_long : null,
      authors: (book.authors || []).map(name => ({ name })),
      firstPublicationYear: parseInt(book.date_published?.substring(0, 4), 10) || null,
      subjects: normalizeGenres(book.subjects),

      externalIds: {
        openLibraryWorkId: null,
        openLibraryEditionId: null,
        goodreadsWorkIds: [],
        amazonASINs: [],
        librarythingIds: [],
        googleBooksVolumeIds: [],
        isbndbIds: [book.isbn13].filter(Boolean),
      },

      editions: [{
        isbn10: book.isbn,
        isbn13: book.isbn13,
        publisher: book.publisher,
        publicationDate: book.date_published,
        binding: book.binding,
        pages: book.pages,
        coverImageURL: book.image,
        synopsis: book.synopsis,
      }].filter(e => e.isbn13), // Only include if has ISBN
    }));

    return {
      success: true,
      provider: 'isbndb',
      works: works,
      totalResults: searchResponse.total || works.length
    };

  } catch (error) {
    console.error(`Error in ISBNdb search for "${title}":`, error);
    return { success: false, error: error.message };
  }
}

export async function getISBNdbEditionsForWork(title, authorName, env) {
  try {
    console.log(`ISBNdb getEditionsForWork ("${title}", "${authorName}")`);
    const searchUrl = `https://api2.isbndb.com/books/${encodeURIComponent(title)}?column=title&language=en&shouldMatchAll=1&pageSize=100`;

    await enforceRateLimit(env);
    const searchResponse = await fetchWithAuth(searchUrl, env);

    if (!searchResponse.books || searchResponse.books.length === 0) {
      return { success: true, editions: [] };
    }

    const relevantBooks = searchResponse.books.filter(book =>
      book.authors?.some(a => a.toLowerCase().includes(authorName.toLowerCase()))
    );

    const cleanedEditions = processAndDeduplicateEditions(relevantBooks);

    cleanedEditions.sort((a, b) => b.qualityScore - a.qualityScore);

    return { success: true, editions: cleanedEditions };

  } catch (error) {
    console.error(`Error in getEditionsForWork for "${title}":`, error);
    return { success: false, error: error.message };
  }
}

export async function getISBNdbBookByISBN(isbn, env) {
  try {
    console.log(`ISBNdb getBookByISBN("${isbn}")`);
    const url = `https://api2.isbndb.com/book/${isbn}?with_prices=0`;
    await enforceRateLimit(env);
    const response = await fetchWithAuth(url, env);
    return { success: true, book: response.book };
  } catch (error) {
    console.error(`Error in getBookByISBN for "${isbn}":`, error);
    return { success: false, error: error.message };
  }
}

function processAndDeduplicateEditions(books) {
  const unwantedTitleKeywords = [
    'study guide', 'summary', 'workbook', 'audiobook', 'box set', 'collection',
    'companion', 'large print', 'classroom', 'abridged', 'collectors', 'deluxe',
    ' unabridged', 'audio cd', 'teacher', 'teaching', 'instructor', 'student edition',
    'annotated', 'critical edition', 'sparknotes', 'cliffsnotes', 'test bank',
    'lesson plan', 'curriculum', 'educational'
  ];
  const unwantedPublishers = [
    'createspace', 'independently published', 'kdp', 'lulu.com',
    'lightning source', 'ingramspark', 'bibliolife', 'apple books', 'smashwords'
  ];

  const editionMap = new Map();

  for (const book of books) {
    const title = (book.title || '').toLowerCase();
    const publisher = (book.publisher || '').toLowerCase();
    const binding = (book.binding || '').toLowerCase();
    const isbn13 = book.isbn13;

    if (!isbn13) continue;
    if (unwantedTitleKeywords.some(keyword => title.includes(keyword))) continue;
    if (unwantedPublishers.some(pub => publisher.includes(pub))) continue;
    if (binding.includes('audio')) continue;

    let score = 50;
    if (book.image) score += 40;
    if (binding.includes('hardcover')) score += 25;
    if (binding.includes('trade paperback')) score += 20;
    if (binding.includes('paperback')) score += 15;
    if (binding.includes('mass market paperback')) score += 5;
    if (binding.includes('library')) score -= 20;
    if (['penguin', 'random house', 'harpercollins', 'simon & schuster', 'hachette', 'macmillan', 'scholastic', 'knopf', 'doubleday', 'viking'].some(p => publisher.includes(p))) {
      score += 15;
    }
    if (book.pages) score += 10;
    if (book.synopsis) score += 5;
    const year = parseInt(book.date_published, 10);
    if (!isNaN(year) && year > 2015) score += 5;

    const currentEdition = {
      isbn13: book.isbn13,
      isbn10: book.isbn,
      title: book.title,
      publisher: book.publisher,
      publishDate: book.date_published,
      binding: book.binding,
      pages: book.pages,
      genres: normalizeGenres(book.subjects),
      coverImageURL: book.image,
      source: 'isbndb',
      qualityScore: score
    };

    if (!editionMap.has(isbn13) || score > editionMap.get(isbn13).qualityScore) {
      editionMap.set(isbn13, currentEdition);
    }
  }

  return Array.from(editionMap.values());
}

function normalizeGenres(subjects) {
  if (!subjects || subjects.length === 0) {
    return [];
  }

  const genreBlacklist = new Set([
    'fiction', 'history', 'biography & autobiography', 'juvenile fiction', 'social science'
  ]);

  const cleanedGenres = subjects
    .map(s => s.split(' / ')[0].trim())
    .filter(s => s.length > 2 && !genreBlacklist.has(s.toLowerCase()))
    .map(s => s.charAt(0).toUpperCase() + s.slice(1));

  if (cleanedGenres.length === 0 && subjects.some(s => s.toLowerCase().includes('juvenile fiction'))) {
    return ['Young Adult'];
  }

  return [...new Set(cleanedGenres)].slice(0, 4);
}

async function fetchWithAuth(url, env) {
  // Handle both secrets store (has .get() method) and direct env var
  const apiKey = env.ISBNDB_API_KEY?.get
    ? await env.ISBNDB_API_KEY.get()
    : env.ISBNDB_API_KEY;

  if (!apiKey) throw new Error('ISBNDB_API_KEY secret not found');
  const response = await fetch(url, {
    headers: { 'Authorization': apiKey, 'Accept': 'application/json' },
  });
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`ISBNdb API error: ${response.status} - ${errorText}`);
  }
  return response.json();
}

async function enforceRateLimit(env) {
  // Use CACHE binding instead of KV_CACHE (unified naming)
  const kvBinding = env.KV_CACHE || env.CACHE;
  if (!kvBinding) {
    console.warn('No KV cache available for rate limiting');
    return;
  }

  const lastRequest = await kvBinding.get(RATE_LIMIT_KEY);
  if (lastRequest) {
    const timeDiff = Date.now() - parseInt(lastRequest);
    if (timeDiff < RATE_LIMIT_INTERVAL) {
      const waitTime = RATE_LIMIT_INTERVAL - timeDiff;
      await new Promise(resolve => setTimeout(resolve, waitTime));
    }
  }
  await kvBinding.put(RATE_LIMIT_KEY, Date.now().toString(), { expirationTtl: 60 });
}

// ============================================================================
// Helper Functions
// ============================================================================

function extractYear(dateString) {
  if (!dateString) return null;
  const yearMatch = dateString.match(/(\d{4})/);
  return yearMatch ? parseInt(yearMatch[1], 10) : null;
}
