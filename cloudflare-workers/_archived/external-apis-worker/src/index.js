import { WorkerEntrypoint } from "cloudflare:workers";
import { searchGoogleBooks, searchGoogleBooksByISBN } from './google-books.js';
import { searchOpenLibrary, getOpenLibraryAuthorWorks } from './open-library.js';
import { searchISBNdb, getISBNdbEditionsForWork, getISBNdbBookByISBN } from './isbndb.js';
import {
  StructuredLogger,
  PerformanceTimer,
  ProviderHealthMonitor
} from '../../structured-logging-infrastructure.js';

export class ExternalAPIsWorker extends WorkerEntrypoint {
  constructor(ctx, env) {
    super(ctx, env);
    // Initialize structured logging (Phase B)
    this.logger = new StructuredLogger('external-apis-worker', env);
    this.providerMonitor = new ProviderHealthMonitor(this.logger);
  }
  async searchGoogleBooks(query, params) {
    const timer = new PerformanceTimer(this.logger, 'rpc_searchGoogleBooks');
    const startTime = Date.now();

    try {
      const result = await searchGoogleBooks(query, params, this.env);
      await this.providerMonitor.recordProviderCall(
        'google_books',
        'search',
        true,
        Date.now() - startTime
      );
      await timer.end({ query, resultsCount: result?.items?.length || 0 });
      return result;
    } catch (error) {
      await this.providerMonitor.recordProviderCall(
        'google_books',
        'search',
        false,
        Date.now() - startTime,
        error.status || 'unknown'
      );
      throw error;
    }
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

  async searchISBNdb(title, authorName) {
    return await searchISBNdb(title, authorName, this.env);
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
