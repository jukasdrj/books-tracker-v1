const USER_AGENT = 'BooksTracker/1.0 (nerd@ooheynerds.com) OpenLibraryWorker/1.1.0';

export async function searchOpenLibrary(query, params = {}, env) {
    try {
      console.log(`RPC: OpenLibrary general search for "${query}"`);

      const maxResults = params.maxResults || 20;

      const searchUrl = `https://openlibrary.org/search.json?q=${encodeURIComponent(query)}&limit=${maxResults}`;
      const response = await fetch(searchUrl, {
        headers: { 'User-Agent': USER_AGENT }
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
      console.error(`RPC Error in OpenLibrary search for "${query}":`, error);
      return { success: false, error: error.message };
    }
}

export async function getOpenLibraryAuthorWorks(authorName, env) {
    try {
      console.log(`RPC: getAuthorWorks("${authorName}")`);

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
      console.error(`RPC Error in getAuthorWorks for "${authorName}":`, error);
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
  const response = await fetch(searchUrl, { headers: { 'User-Agent': USER_AGENT } });
  if (!response.ok) throw new Error('OpenLibrary author search API failed');
  const data = await response.json();
  return data.docs && data.docs.length > 0 ? data.docs[0].key : null;
}

async function getWorksByAuthorKey(authorKey) {
  const worksUrl = `https://openlibrary.org/authors/${authorKey}/works.json?limit=1000`;
  const response = await fetch(worksUrl, { headers: { 'User-Agent': USER_AGENT } });
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
