import { WorkerEntrypoint } from "cloudflare:workers";
import { searchGoogleBooks, searchGoogleBooksByISBN } from './google-books.js';
import { searchOpenLibrary, getOpenLibraryAuthorWorks } from './open-library.js';
import { getISBNdbEditionsForWork, getISBNdbBookByISBN } from './isbndb.js';

export class ExternalAPIsWorker extends WorkerEntrypoint {
  async searchGoogleBooks(query, params) {
    return await searchGoogleBooks(query, params, this.env);
  }

  async searchGoogleBooksByISBN(isbn) {
    return await searchGoogleBooksByISBN(isbn, this.env);
  }

  async searchOpenLibrary(query, params) {
    return await searchOpenLibrary(query, params, this.env);
  }

  async getOpenLibraryAuthorWorks(authorName) {
    return await getOpenLibraryAuthorWorks(authorName, this.env);
  }

  async getISBNdbEditionsForWork(title, authorName) {
    return await getISBNdbEditionsForWork(title, authorName, this.env);
  }

  async getISBNdbBookByISBN(isbn) {
    return await getISBNdbBookByISBN(isbn, this.env);
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === '/health') {
      return new Response(JSON.stringify({ status: 'healthy', worker: 'external-apis-worker' }));
    }
    return new Response('Not Found', { status: 404 });
  }
}

export default ExternalAPIsWorker;
