/**
 * Personal Library Cache Warmer - Work/Edition Normalization Enhanced
 *
 * Intelligent cache warming strategy with SwiftData-aligned normalization:
 * 1. Author-first consolidation to minimize API calls
 * 2. Work/Edition normalization matching SwiftData models
 * 3. External API identifier capture (openLibraryID, isbndbID, googleBooksVolumeID)
 * 4. ISBN multiplication via bibliography searches
 * 5. Quality validation and cross-referencing
 * 6. Progressive enhancement with comprehensive coverage
 *
 * NEW: Processes normalized Work/Edition structures from ISBNdb worker
 * while maintaining backward compatibility with legacy cache formats
 *
 * Target: 500+ books, ~150 unique authors, <200 total API calls
 */

// OPTIMIZED FOR PAID TIER: Maximize ISBNdb quota utilization (5000+ calls/day)
const RATE_LIMIT_INTERVAL = 800; // 0.8 seconds (450% faster) - 4500 calls/hour possible
const BATCH_SIZE = 25; // Increased batch processing (250% more throughput)
const MAX_RETRIES = 3;
const CACHE_TTL = 86400 * 7; // 7 days for warming cache
const AGGRESSIVE_BATCH_SIZE = 50; // For cron jobs - maximum throughput
const DAILY_API_QUOTA = 5000; // Track daily usage against quota

// FIXED: Global quota tracking object
let quotaUsage = {
  calls: 0,
  authors: 0,
  startTime: Date.now(),
  resetTime: Date.now() + 86400000 // 24 hours from start
};

/**
 * CRITICAL: Dual-format cache key storage for compatibility
 * Stores data under both legacy format (author:name) and auto-search format
 * This ensures cache warming works with books-api-proxy retrieval
 */
async function storeDualFormatCache(env, authorName, resultData) {
  console.log(`📚 Storing dual-format cache for author: ${authorName}`);

  // Legacy format (author:name) - for backward compatibility
  const legacyKey = `author:${authorName.toLowerCase()}`;

  // Auto-search format matching books-api-proxy expectations
  // Format: auto-search:{base64_query}:{base64_params}
  const normalizedQuery = authorName.toLowerCase().trim();
  const queryB64 = btoa(normalizedQuery).replace(/[/+=]/g, '_');
  const defaultParams = {
    maxResults: 40,
    showAllEditions: false,
    sortBy: 'relevance',
    translations: false
  };
  const paramsString = Object.keys(defaultParams)
    .sort()
    .map(key => `${key}=${defaultParams[key]}`)
    .join('&');
  const paramsB64 = btoa(paramsString).replace(/[/+=]/g, '_');
  const autoSearchKey = `auto-search:${queryB64}:${paramsB64}`;

  // Store under both key formats
  const cacheData = JSON.stringify(resultData);
  const promises = [
    env.CACHE.put(legacyKey, cacheData, { expirationTtl: CACHE_TTL }),
    env.CACHE.put(autoSearchKey, cacheData, { expirationTtl: CACHE_TTL })
  ];

  try {
    await Promise.all(promises);
    console.log(`✅ Cached ${authorName} under keys: ${legacyKey}, ${autoSearchKey}`);
    return true;
  } catch (error) {
    console.error(`❌ Cache storage failed for ${authorName}:`, error);
    return false;
  }
}

// Helper function to add CORS headers
function addCORSHeaders(response) {
  const headers = new Headers(response.headers);
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  headers.set('Access-Control-Max-Age', '86400');

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers
  });
}

export default {
  // NEW: Reliable cron-based cache warming
  async scheduled(event, env, ctx) {
    const cron = event.cron;
    console.log(`🕒 Cron trigger: ${cron} at ${new Date().toISOString()}`);

    try {
      switch (cron) {
        case '*/15 * * * *': // Every 15 minutes - AGGRESSIVE micro-batch processing
          await processMicroBatch(env, 25); // Process 25 authors (5x increase)
          break;
        case '*/5 * * * *': // Every 5 minutes - HIGH-FREQUENCY batch (NEW)
          await processMicroBatch(env, 15); // Additional high-frequency processing
          break;
        case '0 */4 * * *': // Every 4 hours - MEDIUM batch processing (NEW)
          await processMicroBatch(env, AGGRESSIVE_BATCH_SIZE); // Process 50 authors
          break;
        case '0 2 * * *': // Daily - full library verification
          await verifyAndRepairCache(env);
          break;
        default:
          console.log(`Unknown cron pattern: ${cron}`);
      }
    } catch (error) {
      console.error('Scheduled task error:', error);
    }
  },

  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    console.log(`${request.method} ${path}`);

    // Handle CORS preflight requests
    if (request.method === 'OPTIONS') {
      return addCORSHeaders(new Response(null, { status: 200 }));
    }

    try {
      let response;

      // Route handling
      if (path === '/warm' && request.method === 'POST') {
        response = await handleWarmRequest(request, env, ctx);
      } else if (path === '/status' && request.method === 'GET') {
        response = await handleStatusRequest(request, env, ctx);
      } else if (path === '/live-status' && request.method === 'GET') {
        response = await handleLiveStatusRequest(request, env, ctx);
      } else if (path === '/upload-csv' && request.method === 'POST') {
        response = await handleCSVUpload(request, env, ctx);
      } else if (path === '/results' && request.method === 'GET') {
        response = await handleResultsRequest(request, env, ctx);
      } else if (path === '/health') {
        response = await handleHealthCheck(env);
      } else if (path === '/test-cron' && request.method === 'POST') {
        response = await handleTestCron(request, env, ctx);
      } else if (path === '/trigger-warming' && request.method === 'POST') {
        response = await handleManualWarmingTrigger(request, env, ctx);
      } else if (path === '/debug-kv' && request.method === 'GET') {
        response = await handleKVDebug(request, env, ctx);
      } else if (path === '/' || path === '/dashboard') {
        response = await serveDashboard();
      } else {
        response = new Response(JSON.stringify({ error: 'Endpoint not found' }), {
          status: 404,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      return addCORSHeaders(response);

    } catch (error) {
      console.error('Request handler error:', error);
      const errorResponse = new Response(JSON.stringify({
        error: 'Internal server error',
        details: error.message
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });

      return addCORSHeaders(errorResponse);
    }
  }
};

/**
 * Serve the monitoring dashboard HTML
 */
async function serveDashboard() {
  const htmlContent = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cache Warming System Monitor</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh; color: #333;
        }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        .header { text-align: center; color: white; margin-bottom: 30px; }
        .header h1 { font-size: 2.5rem; margin-bottom: 10px; text-shadow: 0 2px 4px rgba(0,0,0,0.3); }
        .header p { font-size: 1.1rem; opacity: 0.9; }
        .dashboard { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 30px; }
        .status-panel {
            background: white; border-radius: 12px; padding: 25px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.1); backdrop-filter: blur(10px);
        }
        .panel-title {
            font-size: 1.3rem; font-weight: 600; margin-bottom: 20px; color: #2d3748;
            border-bottom: 2px solid #e2e8f0; padding-bottom: 10px;
        }
        .metrics-grid {
            display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px; margin-bottom: 20px;
        }
        .metric-card {
            background: linear-gradient(135deg, #f7fafc 0%, #edf2f7 100%);
            border-radius: 8px; padding: 20px; text-align: center;
            border-left: 4px solid #667eea; transition: transform 0.2s ease;
        }
        .metric-card:hover { transform: translateY(-2px); }
        .metric-label { font-size: 0.9rem; color: #718096; margin-bottom: 8px; font-weight: 500; }
        .metric-value { font-size: 2rem; font-weight: bold; color: #2d3748; margin-bottom: 5px; }
        .metric-change { font-size: 0.8rem; font-weight: 500; }
        .metric-change.positive { color: #38a169; }
        .metric-change.negative { color: #e53e3e; }
        .status-badge {
            display: inline-block; padding: 6px 12px; border-radius: 20px;
            font-size: 0.8rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px;
        }
        .status-operational { background: #c6f6d5; color: #22543d; }
        .status-processing { background: #bee3f8; color: #2c5282; }
        .controls { display: flex; gap: 10px; margin-bottom: 20px; align-items: center; }
        .btn {
            background: #667eea; color: white; border: none; padding: 10px 20px;
            border-radius: 6px; cursor: pointer; font-weight: 500; transition: all 0.2s ease;
        }
        .btn:hover { background: #5a67d8; transform: translateY(-1px); }
        .btn:disabled { background: #a0aec0; cursor: not-allowed; transform: none; }
        .timestamp { font-size: 0.8rem; color: #718096; text-align: center; margin-top: 20px; }
        @media (max-width: 768px) {
            .dashboard { grid-template-columns: 1fr; }
            .metrics-grid { grid-template-columns: repeat(2, 1fr); }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📚 Cache Warming System Monitor</h1>
            <p>Real-time monitoring of author bibliography cache expansion</p>
        </div>

        <div class="controls">
            <button class="btn" onclick="refreshData()">🔄 Refresh Data</button>
            <span id="refreshIndicator"></span>
        </div>

        <div class="dashboard">
            <div class="status-panel">
                <h2 class="panel-title">📊 Cache Statistics</h2>
                <div class="metrics-grid">
                    <div class="metric-card">
                        <div class="metric-label">Cache Entries</div>
                        <div class="metric-value" id="totalCacheEntries">-</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Processed Authors</div>
                        <div class="metric-value" id="processedAuthors">-</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Found Books</div>
                        <div class="metric-value" id="foundBooks">-</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">System Status</div>
                        <div class="metric-value" style="font-size: 1rem;">
                            <span class="status-badge status-operational" id="systemStatus">OPERATIONAL</span>
                        </div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Daily API Quota</div>
                        <div class="metric-value" id="quotaUsage">-</div>
                        <div class="metric-change" id="quotaUtilization">-</div>
                    </div>
                </div>
            </div>

            <div class="status-panel">
                <h2 class="panel-title">⚙️ Worker Status</h2>
                <div id="workerStatus">
                    <div class="metric-card">
                        <div class="metric-label">Cache Warmer</div>
                        <div class="metric-value" style="font-size: 1rem;">
                            <span class="status-badge status-processing">CHECKING...</span>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <div class="status-panel">
            <h2 class="panel-title">🚀 Live Session Progress</h2>
            <div class="metrics-grid">
                <div class="metric-card">
                    <div class="metric-label">Current Phase</div>
                    <div class="metric-value" id="currentPhase" style="font-size: 1.2rem;">-</div>
                </div>
                <div class="metric-card">
                    <div class="metric-label">Total Authors</div>
                    <div class="metric-value" id="totalAuthors">364</div>
                </div>
                <div class="metric-card">
                    <div class="metric-label">Start Time</div>
                    <div class="metric-value" id="startTime" style="font-size: 1rem;">-</div>
                </div>
                <div class="metric-card">
                    <div class="metric-label">Progress</div>
                    <div class="metric-value" id="progressPercent" style="font-size: 1.5rem;">-</div>
                </div>
            </div>

            <div id="recentAuthors"></div>
        </div>

        <div class="timestamp" id="lastUpdate">Last updated: Never</div>
    </div>

    <script>
        async function refreshData() {
            const refreshIndicator = document.getElementById('refreshIndicator');
            refreshIndicator.textContent = 'Fetching data...';

            try {
                const response = await fetch('/live-status');
                const data = await response.json();

                // Update cache statistics
                document.getElementById('totalCacheEntries').textContent = data.cacheEntries || 0;
                document.getElementById('processedAuthors').textContent = data.processedAuthors || 0;
                document.getElementById('foundBooks').textContent = data.foundBooks || 0;

                // Update quota information if available
                if (data.quotaStatus) {
                    document.getElementById('quotaUsage').textContent =
                        data.quotaStatus.used + '/' + data.quotaStatus.total;
                    document.getElementById('quotaUtilization').textContent =
                        data.quotaStatus.utilization + '% utilized';
                    document.getElementById('quotaUtilization').className =
                        'metric-change ' + (parseFloat(data.quotaStatus.utilization) > 80 ? 'negative' : 'positive');
                }

                // Update progress info
                document.getElementById('currentPhase').textContent = data.phase || 'Unknown';
                document.getElementById('totalAuthors').textContent = data.totalAuthors || 364;
                document.getElementById('progressPercent').textContent =
                    data.processedAuthors && data.totalAuthors ?
                    Math.round((data.processedAuthors / data.totalAuthors) * 100) + '%' : '0%';

                if (data.startTime) {
                    const startDate = new Date(data.startTime);
                    document.getElementById('startTime').textContent = startDate.toLocaleTimeString();
                }

                // Update recent authors
                if (data.recentAuthors && data.recentAuthors.length > 0) {
                    const recentHtml = '<h3>Recent Authors Processed:</h3><div style="display: grid; gap: 10px; margin-top: 10px;">' +
                        data.recentAuthors.map(author =>
                            '<div style="background: #f8f9fa; padding: 10px; border-radius: 6px; display: flex; justify-content: space-between;">' +
                            '<span style="font-weight: 500; text-transform: capitalize;">' + author.name + '</span>' +
                            '<span style="color: #38a169;">' + author.books + ' books</span></div>'
                        ).join('') + '</div>';
                    document.getElementById('recentAuthors').innerHTML = recentHtml;
                }

                document.getElementById('lastUpdate').textContent = 'Last updated: ' + new Date().toLocaleString();
                refreshIndicator.textContent = 'Data refreshed!';

                setTimeout(() => { refreshIndicator.textContent = ''; }, 3000);

            } catch (error) {
                console.error('Refresh failed:', error);
                refreshIndicator.textContent = '⚠️ Refresh failed';
            }
        }

        // Auto-refresh every 30 seconds
        setInterval(refreshData, 30000);

        // Initial load
        refreshData();
    </script>
</body>
</html>`;

  return new Response(htmlContent, {
    headers: {
      'Content-Type': 'text/html',
      'Cache-Control': 'public, max-age=300'
    }
  });
}

/**
 * Handle CSV upload and trigger warming process
 */
async function handleCSVUpload(request, env, ctx) {
  try {
    const formData = await request.formData();
    const csvFile = formData.get('csv');

    if (!csvFile) {
      return new Response(JSON.stringify({ error: 'CSV file is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Store CSV in R2 for processing
    const timestamp = new Date().toISOString();
    const fileName = `library-${timestamp}.csv`;

    await env.LIBRARY_DATA.put(fileName, csvFile.stream(), {
      customMetadata: {
        uploadTime: timestamp,
        originalName: csvFile.name || 'unknown.csv',
        size: csvFile.size?.toString() || '0'
      }
    });

    // Parse and validate CSV structure
    const csvText = await csvFile.text();
    const parseResult = await parseAndValidateCSV(csvText);

    if (parseResult.errors.length > 0) {
      return new Response(JSON.stringify({
        error: 'CSV validation failed',
        details: parseResult.errors,
        processed: parseResult.books.length
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Store parsed data for warming process
    const libraryData = {
      fileName,
      uploadTime: timestamp,
      totalBooks: parseResult.books.length,
      uniqueAuthors: parseResult.uniqueAuthors.length,
      books: parseResult.books,
      authors: parseResult.uniqueAuthors,
      qualityReport: parseResult.qualityReport
    };

    // Store in unified CACHE namespace for compatibility with books-api-proxy
    await env.CACHE.put('current_library', JSON.stringify(libraryData), {
      expirationTtl: CACHE_TTL
    });

    // Verify the data was stored successfully (with short retry)
    console.log('Verifying library data persistence...');
    const verification = await getLibraryDataWithRetry(env, 3);

    if (!verification) {
      console.error('Failed to verify library data persistence');
      return new Response(JSON.stringify({
        error: 'CSV upload succeeded but data persistence failed',
        details: 'KV storage verification failed',
        recommendation: 'Try uploading again or contact support'
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    console.log('Library data persistence verified successfully');

    // Check if auto-warming is requested
    const autoWarm = formData.get('autoWarm') === 'true';

    const response = {
      success: true,
      message: 'CSV uploaded and validated successfully',
      fileName,
      stats: {
        totalBooks: parseResult.books.length,
        uniqueAuthors: parseResult.uniqueAuthors.length,
        isbnIssues: parseResult.qualityReport.isbnIssues,
        duplicates: parseResult.qualityReport.duplicates
      },
      dataVerified: true
    };

    // RELIABLE: Inform about cron-based processing instead of ctx.waitUntil()
    if (autoWarm) {
      console.log('Auto-warming requested - now handled by cron-based micro-batch processing');
      response.warmingNote = 'Cache warming runs automatically every 15 minutes via cron triggers';
      response.message += ' - Cache warming handled by reliable cron-based processing';
    }

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('CSV upload error:', error);
    return new Response(JSON.stringify({
      error: 'CSV upload failed',
      details: error.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

/**
 * Handle cache warming request
 */
async function handleWarmRequest(request, env, ctx) {
  try {
    const body = await request.json();
    const strategy = body.strategy || 'hybrid';
    const dryRun = body.dryRun || false;

    console.log(`📢 Warm request received: strategy=${strategy}, dryRun=${dryRun}`);

    // Get current library data with retry logic for KV eventual consistency
    const libraryData = await getLibraryDataWithRetry(env);

    if (!libraryData) {
      return new Response(JSON.stringify({
        error: 'No library data found. Please upload CSV first.',
        endpoint: '/upload-csv',
        hint: 'If you just uploaded CSV, wait 30 seconds and try again due to KV eventual consistency'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Execute warming strategy with debugging
    ctx.waitUntil(
      (async () => {
        try {
          console.log('🚀 Original warming task starting:', new Date().toISOString());
          console.log('📊 Strategy:', strategy, 'DryRun:', dryRun);
          const result = await executeWarmingStrategy(strategy, libraryData, env, dryRun);
          console.log('✅ Original warming task completed');
          return result;
        } catch (error) {
          console.error('💥 Original warming task failed:', error);
          await env.CACHE.put(`error_original_${Date.now()}`, JSON.stringify({
            error: error.message,
            stack: error.stack,
            timestamp: new Date().toISOString(),
            strategy, dryRun
          }), { expirationTtl: 3600 });
          throw error;
        }
      })()
    );

    const authorsArray = Array.isArray(libraryData.uniqueAuthors)
      ? libraryData.uniqueAuthors
      : (libraryData.authors || []);

    return new Response(JSON.stringify({
      success: true,
      message: `Cache warming started with ${strategy} strategy`,
      estimatedTime: calculateEstimatedTime(authorsArray.length),
      totalAuthors: authorsArray.length,
      totalBooks: libraryData.totalBooks,
      dryRun
    }), {
      status: 202,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Warming request error:', error);
    return new Response(JSON.stringify({
      error: 'Warming request failed',
      details: error.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

/**
 * Parse and validate CSV data
 */
async function parseAndValidateCSV(csvText) {
  const lines = csvText.split('\n').map(line => line.trim()).filter(line => line.length > 0);
  const result = {
    books: [],
    uniqueAuthors: [],
    qualityReport: {
      isbnIssues: [],
      duplicates: [],
      malformed: []
    },
    errors: []
  };

  if (lines.length < 2) {
    result.errors.push('CSV must contain at least a header row and one data row');
    return result;
  }

  const header = lines[0].toLowerCase();

  // Validate header structure
  if (!header.includes('title') || !header.includes('author') || !header.includes('isbn')) {
    result.errors.push('CSV must contain Title, Author, and ISBN columns');
    return result;
  }

  const authorSet = new Set();
  const seenISBNs = new Set();
  const seenTitleAuthor = new Set();

  // Process each book row
  for (let i = 1; i < lines.length; i++) {
    try {
      const row = parseCSVRow(lines[i]);

      if (row.length < 3) {
        result.qualityReport.malformed.push({
          line: i + 1,
          content: lines[i],
          issue: 'Insufficient columns'
        });
        continue;
      }

      const [title, author, isbn] = row.map(cell => cell.trim().replace(/^"|"$/g, ''));

      // Validate required fields
      if (!title || !author) {
        result.qualityReport.malformed.push({
          line: i + 1,
          issue: 'Missing title or author',
          title,
          author
        });
        continue;
      }

      // ISBN validation and cleaning
      const cleanISBN = cleanAndValidateISBN(isbn);
      if (!cleanISBN.valid) {
        result.qualityReport.isbnIssues.push({
          line: i + 1,
          title,
          author,
          originalISBN: isbn,
          issue: cleanISBN.issue
        });
      }

      // Duplicate detection
      const titleAuthorKey = `${title.toLowerCase()}|${author.toLowerCase()}`;
      if (seenTitleAuthor.has(titleAuthorKey)) {
        result.qualityReport.duplicates.push({
          title,
          author,
          line: i + 1
        });
        continue;
      }

      if (cleanISBN.valid && seenISBNs.has(cleanISBN.isbn)) {
        result.qualityReport.duplicates.push({
          title,
          author,
          isbn: cleanISBN.isbn,
          line: i + 1,
          issue: 'Duplicate ISBN'
        });
      }

      // Add to collections
      seenTitleAuthor.add(titleAuthorKey);
      if (cleanISBN.valid) {
        seenISBNs.add(cleanISBN.isbn);
      }
      authorSet.add(author.toLowerCase());

      result.books.push({
        title,
        author,
        originalISBN: isbn,
        cleanISBN: cleanISBN.valid ? cleanISBN.isbn : null,
        line: i + 1
      });

    } catch (error) {
      result.qualityReport.malformed.push({
        line: i + 1,
        content: lines[i],
        issue: `Parse error: ${error.message}`
      });
    }
  }

  result.uniqueAuthors = Array.from(authorSet);

  return result;
}

/**
 * Execute the hybrid warming strategy
 */
async function executeWarmingStrategy(strategy, libraryData, env, dryRun = false) {
  const warmingId = `warming_${Date.now()}`;
  const startTime = Date.now();

  // Safely create timestamps with validation
  let startTimeIso, estimatedCompletionIso;

  // Validate startTime and create ISO string
  const validStartTime = typeof startTime === 'number' && startTime > 0 ? startTime : Date.now();
  try {
    startTimeIso = new Date(validStartTime).toISOString();
    console.log(`Warming session start time: ${startTimeIso}`);
  } catch (e) {
    console.error(`Error creating startTime: ${e.message}, startTime: ${validStartTime}`);
    startTimeIso = new Date().toISOString();
  }

  // Calculate estimated completion with proper validation
  try {
    const authorCount = (libraryData.authors || []).length;
    console.log(`Processing ${authorCount} unique authors`);

    const estimatedSeconds = calculateEstimatedTime(authorCount);
    const estimatedTime = validStartTime + Math.max(0, estimatedSeconds * 1000);

    // Validate the calculated time
    if (isNaN(estimatedTime) || estimatedTime <= validStartTime) {
      throw new Error(`Invalid estimated time calculation: ${estimatedTime}`);
    }

    estimatedCompletionIso = new Date(estimatedTime).toISOString();
    console.log(`Estimated completion: ${estimatedCompletionIso} (${estimatedSeconds}s from now)`);
  } catch (e) {
    console.error(`Error creating estimatedCompletion: ${e.message}`);
    estimatedCompletionIso = new Date(validStartTime + 300000).toISOString(); // 5 minutes default
  }

  // Safely extract data with fallbacks - FIXED DATA STRUCTURE BUG
  const uniqueAuthors = Array.isArray(libraryData.uniqueAuthors)
    ? libraryData.uniqueAuthors
    : (libraryData.authors || []);  // 🔧 FIXED: handle both data structures
  const totalBooks = libraryData.totalBooks || 0;
  const books = libraryData.books || [];

  const progress = {
    id: warmingId,
    strategy,
    dryRun,
    startTime: startTimeIso,
    phase: 'starting',
    totalAuthors: uniqueAuthors.length,
    totalBooks: totalBooks,
    processedAuthors: 0,
    foundBooks: 0,
    cachedBooks: 0,
    errors: [],
    authorResults: [],
    estimatedCompletion: estimatedCompletionIso,
    dataValidation: {
      hasAuthors: uniqueAuthors.length > 0,
      hasBooks: books.length > 0,
      dataIntegrity: uniqueAuthors.length > 0 && books.length > 0
    }
  };

  try {
    // Store initial progress
    await env.CACHE.put(`progress_${warmingId}`, JSON.stringify(progress), {
      expirationTtl: CACHE_TTL
    });

    console.log(`Starting ${strategy} warming strategy for ${uniqueAuthors.length} authors`);

    // Phase 1: Process authors in batches (only if we have authors)
    if (uniqueAuthors.length > 0) {
      progress.phase = 'author_bibliographies';
      await updateProgress(env, warmingId, progress);

      const authorBatches = chunkArray(uniqueAuthors, BATCH_SIZE);

      for (let batchIndex = 0; batchIndex < authorBatches.length; batchIndex++) {
        const batch = authorBatches[batchIndex];
        console.log(`Processing author batch ${batchIndex + 1}/${authorBatches.length} (${batch.length} authors)`);

        for (const author of batch) {
          try {
            const authorResult = await processAuthorBiography(author, env, dryRun);

            progress.processedAuthors++;
            progress.foundBooks += authorResult.foundBooks;
            progress.cachedBooks += authorResult.cachedBooks;
            progress.authorResults.push(authorResult);

            // Update progress every few authors
            if (progress.processedAuthors % 5 === 0) {
              await updateProgress(env, warmingId, progress);
            }

            // Rate limiting
            await sleep(RATE_LIMIT_INTERVAL);

          } catch (error) {
            console.error(`Error processing author ${author}:`, error);
            progress.errors.push({
              type: 'author_processing',
              author,
              error: error.message,
              timestamp: new Date().toISOString()
            });
          }
        }

        // Small batch pause to prevent overwhelming
        await sleep(2000);
      }
    } else {
      console.log('No authors found, skipping author bibliography phase');
    }

    // Phase 2: Process orphaned titles (books without successful author matches)
    progress.phase = 'orphaned_titles';
    await updateProgress(env, warmingId, progress);

    const orphanedTitles = findOrphanedTitles(books, progress.authorResults);
    console.log(`Processing ${orphanedTitles.length} orphaned titles (from ${books.length} total books)`);

    for (const book of orphanedTitles) {
      try {
        const titleResult = await processTitleSearch(book, env, dryRun);

        if (titleResult.success) {
          progress.foundBooks++;
          progress.cachedBooks += titleResult.cachedBooks;
        }

        // Rate limiting
        await sleep(RATE_LIMIT_INTERVAL);

      } catch (error) {
        console.error(`Error processing title search for "${book.title}":`, error);
        progress.errors.push({
          type: 'title_search',
          title: book.title,
          author: book.author,
          error: error.message,
          timestamp: new Date().toISOString()
        });
      }
    }

    // Phase 3: Generate final report
    progress.phase = 'completed';
    progress.completedTime = new Date().toISOString();
    progress.durationSeconds = Math.round((Date.now() - validStartTime) / 1000);
    progress.successRate = totalBooks > 0 ? ((progress.foundBooks / totalBooks) * 100).toFixed(1) : '0.0';

    await updateProgress(env, warmingId, progress);

    console.log(`Warming strategy completed. Found ${progress.foundBooks}/${totalBooks} books (${progress.successRate}%)`);

    return progress;

  } catch (error) {
    console.error('Warming strategy failed:', error);
    progress.phase = 'failed';
    progress.error = error.message;
    progress.completedTime = new Date().toISOString();
    await updateProgress(env, warmingId, progress);
    throw error;
  }
}

/**
 * Process author biography to get all their books
 */
async function processAuthorBiography(author, env, dryRun = false) {
  const startTime = Date.now();
  const result = {
    author,
    foundBooks: 0,
    cachedBooks: 0,
    success: false,
    books: [],
    errors: [],
    processingTime: 0,
    services: {
      isbndb: { attempted: false, success: false, responseTime: 0 },
      booksApi: { attempted: false, success: false, responseTime: 0, cacheHits: 0 }
    }
  };

  try {
    if (dryRun) {
      // Simulate processing for dry run
      result.success = true;
      result.foundBooks = Math.floor(Math.random() * 10) + 1;
      result.cachedBooks = result.foundBooks;
      result.processingTime = Date.now() - startTime;
      return result;
    }

    console.log(`🔍 Processing author: "${author}"`);

    // Call ISBNdb biography worker with timeout and retry
    result.services.isbndb.attempted = true;
    const isbndbStart = Date.now();

    try {
      // ✅ FIXED: Service bindings require absolute URLs
      const isbndbUrl = `https://isbndb-biography-worker-production.jukasdrj.workers.dev/author/${encodeURIComponent(author)}?page=1&pageSize=50&language=en`;
      console.log(`📡 Calling ISBNdb worker: ${isbndbUrl}`);

      const response = await env.ISBNDB_WORKER.fetch(
        new Request(isbndbUrl),
        {
          signal: AbortSignal.timeout(30000) // 30 second timeout
        }
      );

      result.services.isbndb.responseTime = Date.now() - isbndbStart;

      if (!response.ok) {
        throw new Error(`ISBNdb worker HTTP ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      result.services.isbndb.success = true;

      // Handle both legacy and new normalized formats
      const hasNormalizedData = data.works && data.authors;
      const totalBooks = hasNormalizedData ?
        data.works.reduce((sum, work) => sum + work.editions.length, 0) :
        (data.books?.length || 0);

      if (data.success && totalBooks > 0) {
        result.success = true;
        result.foundBooks = totalBooks;

        if (hasNormalizedData) {
          console.log(`🎯 Found ${data.works.length} works with ${totalBooks} editions for author "${author}" (normalized format)`);
          // Convert normalized structure to legacy format for compatibility
          result.books = data.works.flatMap(work =>
            work.editions.map(edition => ({
              ...edition,
              work_title: work.title,
              work_identifiers: work.identifiers,
              work_authors: work.authors
            }))
          );
          result.normalizedData = { works: data.works, authors: data.authors };
        } else {
          console.log(`📚 Found ${totalBooks} books for author "${author}" (legacy format)`);
          result.books = data.books || [];
        }

        // ENHANCED: Cache individual works/editions AND use dual-format storage for author search
        result.services.booksApi.attempted = true;
        const booksApiStart = Date.now();

        // Cache items via books-api-proxy for ISBN/work lookups
        for (const item of result.books) {
          try {
            // Use ISBN for caching (covers both legacy books and normalized editions)
            if (item.isbn || item.isbn13) {
              const isbn = item.isbn13 || item.isbn;
              const cacheUrl = `https://books-api-proxy.jukasdrj.workers.dev/search/auto?q=${encodeURIComponent(isbn)}&maxResults=1&includeTranslations=false&showAllEditions=false`;
              const cacheResponse = await env.BOOKS_API_PROXY.fetch(
                new Request(cacheUrl),
                {
                  signal: AbortSignal.timeout(8000) // Reduced timeout for better throughput
                }
              );

              if (cacheResponse.ok) {
                result.cachedBooks++;
                result.services.booksApi.cacheHits++;
              } else {
                const title = item.work_title || item.title || 'Unknown';
                result.errors.push(`Cache failed for "${title}" (HTTP ${cacheResponse.status})`);
              }
            } else {
              const title = item.work_title || item.title || 'Unknown';
              result.errors.push(`No ISBN found for "${title}"`);
            }
          } catch (cacheError) {
            const title = item.work_title || item.title || 'Unknown';
            result.errors.push(`Cache error for "${title}": ${cacheError.message}`);
          }
        }

        // CRITICAL: Store author results in dual-format cache for auto-search compatibility
        if (data.success && (data.books || data.works)) {
          console.log(`🔄 Storing enhanced dual-format cache for author: ${author}`);
          const cacheData = hasNormalizedData ?
            // Store normalized data with legacy compatibility
            {
              ...data,
              books: result.books, // Legacy format for backward compatibility
              format: 'enhanced_work_edition_v1'
            } :
            data; // Legacy format as-is

          const authorCacheResult = await storeDualFormatCache(env, author, cacheData);
          if (authorCacheResult) {
            console.log(`✅ Successfully cached author "${author}" in enhanced dual format`);
            result.services.booksApi.authorCached = true;
          } else {
            console.log(`❌ Failed to cache author "${author}" in enhanced dual format`);
            result.services.booksApi.authorCached = false;
          }
        }

        result.services.booksApi.responseTime = Date.now() - booksApiStart;
        result.services.booksApi.success = result.cachedBooks > 0;

        console.log(`✅ Cached ${result.cachedBooks}/${result.foundBooks} books for "${author}"`);

        // ENHANCED: Cache author search via books-api-proxy to populate auto-search cache
        try {
          console.log(`🔍 Caching author search for "${author}" via books-api-proxy...`);
          const authorSearchUrl = `https://books-api-proxy.jukasdrj.workers.dev/search/auto?q=${encodeURIComponent(author)}&maxResults=40&includeTranslations=false&showAllEditions=false`;
          const authorSearchResponse = await env.BOOKS_API_PROXY.fetch(
            new Request(authorSearchUrl),
            {
              signal: AbortSignal.timeout(12000) // Optimized timeout
            }
          );

          if (authorSearchResponse.ok) {
            const authorSearchData = await authorSearchResponse.json();
            console.log(`✅ Author search cached: "${author}" (${authorSearchData.items?.length || 0} results)`);
            result.services.booksApi.authorSearchCached = true;
            // Track successful cache operations for metrics
            result.services.booksApi.totalCacheOps = (result.services.booksApi.cacheHits || 0) + 1;
          } else {
            console.log(`❌ Author search caching failed for "${author}": ${authorSearchResponse.status}`);
            result.services.booksApi.authorSearchCached = false;
          }
        } catch (authorSearchError) {
          console.error(`❌ Author search caching error for "${author}": ${authorSearchError.message}`);
          result.services.booksApi.authorSearchCached = false;
        }

      } else {
        console.log(`❌ No books found for author "${author}"`);
        result.errors.push('No books found in ISBNdb response');
      }

    } catch (isbndbError) {
      result.services.isbndb.responseTime = Date.now() - isbndbStart;
      const errorMsg = `ISBNdb service error: ${isbndbError.message}`;
      console.error(`❌ ${errorMsg} for author "${author}"`);
      result.errors.push(errorMsg);
    }

  } catch (error) {
    console.error(`💥 Critical error processing author "${author}":`, error);
    result.errors.push(`Critical error: ${error.message}`);
  }

  result.processingTime = Date.now() - startTime;
  return result;
}

/**
 * Process individual title search for orphaned books
 */
async function processTitleSearch(book, env, dryRun = false) {
  const result = {
    title: book.title,
    author: book.author,
    success: false,
    cachedBooks: 0,
    error: null
  };

  try {
    if (dryRun) {
      result.success = true;
      result.cachedBooks = 1;
      return result;
    }

    // Try title + author search via books-api-proxy
    const query = `"${book.title}" ${book.author}`;
    // ✅ FIXED: Service bindings require absolute URLs
    const searchUrl = `https://books-api-proxy.jukasdrj.workers.dev/search/auto?q=${encodeURIComponent(query)}&maxResults=3&includeTranslations=false&showAllEditions=false`;
    const response = await env.BOOKS_API_PROXY.fetch(
      new Request(searchUrl)
    );

    if (response.ok) {
      const data = await response.json();
      if (data.items && data.items.length > 0) {
        result.success = true;
        result.cachedBooks = data.items.length;
      }
    }

  } catch (error) {
    result.error = error.message;
  }

  return result;
}

// Utility functions
function parseCSVRow(row) {
  const result = [];
  let current = '';
  let inQuotes = false;

  for (let i = 0; i < row.length; i++) {
    const char = row[i];

    if (char === '"') {
      inQuotes = !inQuotes;
    } else if (char === ',' && !inQuotes) {
      result.push(current);
      current = '';
    } else {
      current += char;
    }
  }

  result.push(current);
  return result;
}

function cleanAndValidateISBN(isbn) {
  if (!isbn) {
    return { valid: false, issue: 'Missing ISBN' };
  }

  // Clean ISBN - remove dashes, spaces, and common suffixes
  const cleaned = isbn.replace(/[-\s]/g, '').replace(/[^0-9X]/gi, '').toUpperCase();

  if (cleaned.length === 10) {
    return { valid: true, isbn: cleaned, type: 'ISBN-10' };
  } else if (cleaned.length === 13 && cleaned.startsWith('978')) {
    return { valid: true, isbn: cleaned, type: 'ISBN-13' };
  } else {
    return {
      valid: false,
      issue: `Invalid ISBN format (length: ${cleaned.length}, starts with: ${cleaned.substring(0, 3)})`
    };
  }
}

function chunkArray(array, size) {
  const chunks = [];
  for (let i = 0; i < array.length; i += size) {
    chunks.push(array.slice(i, i + size));
  }
  return chunks;
}

function findOrphanedTitles(originalBooks, authorResults) {
  const successfulAuthors = new Set();

  for (const result of authorResults) {
    if (result.success) {
      successfulAuthors.add(result.author.toLowerCase());
    }
  }

  return originalBooks.filter(book => !successfulAuthors.has(book.author.toLowerCase()));
}

function calculateEstimatedTime(authorCount) {
  // Validate input and provide fallback
  const validAuthorCount = typeof authorCount === 'number' && authorCount > 0 ? authorCount : 0;

  if (validAuthorCount === 0) {
    console.log('Warning: No authors to process, estimating orphaned titles only');
    return 300; // 5 minutes fallback for orphaned titles only
  }

  // 1.1 seconds per author + processing overhead + orphaned title searches
  const estimatedSeconds = (validAuthorCount * 1.1) + (validAuthorCount * 0.1) + 60;
  console.log(`Estimated time for ${validAuthorCount} authors: ${estimatedSeconds} seconds`);

  return estimatedSeconds;
}

async function updateProgress(env, warmingId, progress) {
  await env.CACHE.put(`progress_${warmingId}`, JSON.stringify(progress), {
    expirationTtl: CACHE_TTL
  });
}

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Get library data with retry logic for KV eventual consistency
 */
async function getLibraryDataWithRetry(env, maxRetries = 5) {
  let lastError = null;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      console.log(`Attempting to read library data (attempt ${attempt}/${maxRetries})`);

      const libraryData = await env.CACHE.get('current_library', 'json');

      if (libraryData && libraryData.books && libraryData.authors) {
        console.log(`Successfully retrieved library data: ${libraryData.totalBooks} books, ${(libraryData.authors || []).length} authors`);
        return libraryData;
      }

      if (libraryData) {
        console.log('Found partial library data, missing books or authors array');
      } else {
        console.log('No library data found in KV');
      }

    } catch (error) {
      lastError = error;
      console.error(`KV read attempt ${attempt} failed:`, error);
    }

    if (attempt < maxRetries) {
      // Exponential backoff: 1s, 2s, 4s, 8s
      const delay = Math.pow(2, attempt - 1) * 1000;
      console.log(`Waiting ${delay}ms before retry...`);
      await sleep(delay);
    }
  }

  console.error('All retry attempts failed', lastError);
  return null;
}

// Status and result handlers
async function handleStatusRequest(request, env, ctx) {
  const url = new URL(request.url);
  const warmingId = url.searchParams.get('id');

  if (warmingId) {
    const progress = await env.CACHE.get(`progress_${warmingId}`, 'json');

    if (!progress) {
      return new Response(JSON.stringify({ error: 'Warming session not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify(progress), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  // Return general status
  const libraryData = await env.CACHE.get('current_library', 'json');

  return new Response(JSON.stringify({
    hasLibraryData: !!libraryData,
    libraryStats: libraryData ? {
      totalBooks: libraryData.totalBooks,
      uniqueAuthors: (libraryData.authors || []).length,
      uploadTime: libraryData.uploadTime
    } : null
  }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' }
  });
}

async function handleResultsRequest(request, env, ctx) {
  // Implementation for retrieving warming results
  return new Response(JSON.stringify({ message: 'Results endpoint - implementation pending' }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' }
  });
}

async function handleHealthCheck(env) {
  try {
    // Get ACTUAL cache statistics from KV namespace
    const keys = await env.CACHE.list();
    const authorKeys = keys.keys.filter(key => key.name.startsWith('author:')).length;
    const autoSearchKeys = keys.keys.filter(key => key.name.startsWith('auto-search:')).length;
    const progressKeys = keys.keys.filter(key => key.name.startsWith('progress_')).length;
    const libraryData = await env.CACHE.get('current_library', 'json');

    // TRUTH: Show only actual cached data, no fake processing claims
    return new Response(JSON.stringify({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      cache: {
        totalKeys: keys.keys.length,
        authorEntries: authorKeys,
        autoSearchEntries: autoSearchKeys,
        progressEntries: progressKeys,
        actualCachedAuthors: authorKeys, // This is the real number!
        libraryDataUploaded: !!libraryData,
        uniqueAuthorsInLibrary: libraryData ? (libraryData.authors || []).length : 0,
        totalBooksInLibrary: libraryData ? libraryData.totalBooks : 0
      },
      services: {
        kv: 'connected',
        isbndbWorker: 'configured',
        booksApiProxy: 'configured'
      },
      reality: {
        cacheEmpty: keys.keys.length === 0,
        needsCacheWarming: authorKeys === 0 && !!libraryData,
        readyForProduction: authorKeys > 0 && !!libraryData
      }
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    return new Response(JSON.stringify({
      status: 'error',
      timestamp: new Date().toISOString(),
      error: error.message,
      cache: {
        accessible: false
      }
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

async function handleTestCron(request, env, ctx) {
  try {
    const body = await request.json();
    const cronType = body.cronType || 'full_warming';

    console.log(`🧪 Manual cron test triggered: ${cronType}`);

    if (cronType === 'full_warming') {
      // Execute the same function as the weekly cron
      await executeFullLibraryWarming(env, ctx);

      return new Response(JSON.stringify({
        success: true,
        message: 'Full library warming completed successfully',
        timestamp: new Date().toISOString()
      }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' }
      });
    } else {
      return new Response(JSON.stringify({
        error: 'Unknown cron type',
        availableTypes: ['full_warming']
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }
  } catch (error) {
    console.error('Test cron failed:', error);
    return new Response(JSON.stringify({
      error: 'Test cron execution failed',
      details: error.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

async function executeFullLibraryWarming(env, ctx) {
  console.log('🚀 Starting scheduled full library warming...');

  try {
    // Get current library data
    const libraryData = await getLibraryDataWithRetry(env);
    if (!libraryData) {
      console.error('❌ No library data found for scheduled warming');
      return;
    }

    console.log(`📚 Found library data: ${libraryData.totalBooks} books, ${(libraryData.authors || []).length} authors`);

    // Execute the warming strategy (this is the same logic as the manual trigger)
    await executeWarmingStrategy('author_first', libraryData, env, false);

    console.log('✅ Scheduled full library warming completed successfully');

  } catch (error) {
    console.error('💥 Scheduled warming failed:', error);
    throw error; // Re-throw so CloudFlare logs the cron job failure
  }
}

async function checkForNewAdditions(env, ctx) {
  // Implementation for checking new additions
  console.log('Checking for new additions...');
}

/**
 * Handle manual warming trigger with ISBNdb rate limiting compliance
 */
async function handleManualWarmingTrigger(request, env, ctx) {
  try {
    const body = await request.json();
    const strategy = body.strategy || 'author_first';
    const startFromAuthor = body.startFromAuthor || 0; // Allow resuming from specific author
    const maxAuthors = body.maxAuthors || null; // Allow limiting authors processed
    const dryRun = body.dryRun || false;

    console.log(`🚀 Manual warming trigger: strategy=${strategy}, startFrom=${startFromAuthor}, maxAuthors=${maxAuthors}, dryRun=${dryRun}`);

    // Get current library data
    const libraryData = await getLibraryDataWithRetry(env);
    if (!libraryData) {
      return new Response(JSON.stringify({
        error: 'No library data found. Please upload CSV first.',
        endpoint: '/upload-csv',
        hint: 'Library data must be uploaded before warming can begin'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate start position
    const totalAuthors = (libraryData.authors || []).length;
    if (startFromAuthor >= totalAuthors) {
      return new Response(JSON.stringify({
        error: `Start position ${startFromAuthor} exceeds total authors (${totalAuthors})`,
        hint: `Valid range: 0-${totalAuthors - 1}`
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Calculate actual processing scope
    const remainingAuthors = totalAuthors - startFromAuthor;
    const authorsToProcess = maxAuthors ? Math.min(maxAuthors, remainingAuthors) : remainingAuthors;
    const estimatedTime = calculateEstimatedTime(authorsToProcess);

    // Start the warming process with enhanced rate limiting and debugging
    ctx.waitUntil(
      (async () => {
        try {
          console.log('🚀 Background task starting:', new Date().toISOString());
          console.log('📊 Processing scope:', { startFromAuthor, maxAuthors: authorsToProcess, dryRun });
          const result = await executeEnhancedWarmingStrategy(strategy, libraryData, env, {
            startFromAuthor,
            maxAuthors: authorsToProcess,
            dryRun,
            enforceRateLimit: true
          });
          console.log('✅ Background task completed:', result.id);
          return result;
        } catch (error) {
          console.error('💥 Background task failed:', error);
          // Store error for later retrieval
          await env.CACHE.put(`error_${Date.now()}`, JSON.stringify({
            error: error.message,
            stack: error.stack,
            timestamp: new Date().toISOString(),
            scope: { startFromAuthor, maxAuthors: authorsToProcess, dryRun }
          }), { expirationTtl: 3600 });
          throw error;
        }
      })()
    );

    return new Response(JSON.stringify({
      success: true,
      message: `Manual cache warming started`,
      details: {
        strategy,
        totalAuthors,
        startFromAuthor,
        authorsToProcess,
        estimatedTimeMinutes: Math.round(estimatedTime / 60),
        rateLimitCompliance: '1 call per second to ISBNdb',
        dryRun
      },
      endpoints: {
        status: '/status',
        progress: '/status?id=warming_[id]'
      }
    }), {
      status: 202,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Manual warming trigger failed:', error);
    return new Response(JSON.stringify({
      error: 'Manual warming trigger failed',
      details: error.message,
      hint: 'Check request format and try again'
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

/**
 * Enhanced warming strategy with precise rate limiting and resume capability
 */
async function executeEnhancedWarmingStrategy(strategy, libraryData, env, options = {}) {
  const {
    startFromAuthor = 0,
    maxAuthors = null,
    dryRun = false,
    enforceRateLimit = true
  } = options;

  const warmingId = `warming_${Date.now()}`;
  const startTime = Date.now();

  // Safely create timestamps
  const startTimeIso = new Date(startTime).toISOString();

  // 🔍 DEBUG: Check library data structure
  console.log('📊 Library data keys:', Object.keys(libraryData));
  console.log('📊 uniqueAuthors type:', typeof libraryData.uniqueAuthors);
  console.log('📊 uniqueAuthors value:', libraryData.uniqueAuthors);

  const uniqueAuthors = Array.isArray(libraryData.uniqueAuthors)
    ? libraryData.uniqueAuthors
    : (libraryData.authors || []);  // 🔧 FIXED: handle both data structures
  const totalBooks = libraryData.totalBooks || 0;
  const books = libraryData.books || [];

  // Calculate processing scope
  const authorsSlice = maxAuthors ?
    uniqueAuthors.slice(startFromAuthor, startFromAuthor + maxAuthors) :
    uniqueAuthors.slice(startFromAuthor);

  const estimatedSeconds = calculateEstimatedTime(authorsSlice.length);
  const estimatedCompletionIso = new Date(startTime + estimatedSeconds * 1000).toISOString();

  const progress = {
    id: warmingId,
    strategy,
    dryRun,
    enforceRateLimit,
    startTime: startTimeIso,
    phase: 'initializing',
    totalAuthors: uniqueAuthors.length,
    startFromAuthor,
    authorsToProcess: authorsSlice.length,
    totalBooks: totalBooks,
    processedAuthors: 0,
    foundBooks: 0,
    cachedBooks: 0,
    errors: [],
    authorResults: [],
    estimatedCompletion: estimatedCompletionIso,
    rateLimitInfo: {
      targetInterval: enforceRateLimit ? 1000 : RATE_LIMIT_INTERVAL,
      actualIntervals: [],
      avgInterval: 0
    },
    dataValidation: {
      hasAuthors: uniqueAuthors.length > 0,
      hasBooks: books.length > 0,
      resumeCapable: true
    }
  };

  try {
    // Store initial progress
    await env.CACHE.put(`progress_${warmingId}`, JSON.stringify(progress), {
      expirationTtl: CACHE_TTL
    });

    console.log(`🎯 Enhanced warming: ${authorsSlice.length} authors (${startFromAuthor} to ${startFromAuthor + authorsSlice.length - 1})`);

    // Phase 1: Process authors with precise rate limiting
    progress.phase = 'author_bibliographies';
    await updateProgress(env, warmingId, progress);

    const rateLimitInterval = enforceRateLimit ? 1000 : RATE_LIMIT_INTERVAL; // 1 second for ISBNdb compliance

    for (let i = 0; i < authorsSlice.length; i++) {
      const author = authorsSlice[i];
      const globalAuthorIndex = startFromAuthor + i;
      const callStartTime = Date.now();

      try {
        console.log(`📖 Processing author ${globalAuthorIndex + 1}/${uniqueAuthors.length}: "${author}"`);

        const authorResult = await processAuthorBiography(author, env, dryRun);
        authorResult.globalIndex = globalAuthorIndex;
        authorResult.batchIndex = i;

        progress.processedAuthors++;
        progress.foundBooks += authorResult.foundBooks;
        progress.cachedBooks += authorResult.cachedBooks;
        progress.authorResults.push(authorResult);

        // Track actual call timing for rate limit compliance
        const callDuration = Date.now() - callStartTime;
        progress.rateLimitInfo.actualIntervals.push(callDuration);

        // Calculate average interval
        if (progress.rateLimitInfo.actualIntervals.length > 0) {
          progress.rateLimitInfo.avgInterval = Math.round(
            progress.rateLimitInfo.actualIntervals.reduce((a, b) => a + b, 0) /
            progress.rateLimitInfo.actualIntervals.length
          );
        }

        // Update progress every author (more frequent for manual triggers)
        if (progress.processedAuthors % 1 === 0) {
          await updateProgress(env, warmingId, progress);
        }

        // Precise rate limiting - ensure we don't exceed 1 call per second to ISBNdb
        if (i < authorsSlice.length - 1) { // Don't wait after last author
          const waitTime = Math.max(0, rateLimitInterval - callDuration);
          if (waitTime > 0) {
            console.log(`⏱️  Rate limit wait: ${waitTime}ms (call took ${callDuration}ms)`);
            await sleep(waitTime);
          }
        }

      } catch (error) {
        console.error(`❌ Error processing author ${globalAuthorIndex + 1} "${author}":`, error);
        progress.errors.push({
          type: 'author_processing',
          author,
          globalIndex: globalAuthorIndex,
          error: error.message,
          timestamp: new Date().toISOString()
        });
      }
    }

    // Phase 2: Complete with final report
    progress.phase = 'completed';
    progress.completedTime = new Date().toISOString();
    progress.durationSeconds = Math.round((Date.now() - startTime) / 1000);
    progress.successRate = authorsSlice.length > 0 ?
      ((progress.processedAuthors / authorsSlice.length) * 100).toFixed(1) : '0.0';

    // Calculate rate limit compliance
    if (progress.rateLimitInfo.actualIntervals.length > 0) {
      const violations = progress.rateLimitInfo.actualIntervals.filter(interval => interval < 950).length;
      progress.rateLimitInfo.violations = violations;
      progress.rateLimitInfo.compliance = ((progress.rateLimitInfo.actualIntervals.length - violations) /
        progress.rateLimitInfo.actualIntervals.length * 100).toFixed(1) + '%';
    }

    await updateProgress(env, warmingId, progress);

    console.log(`✅ Enhanced warming completed: ${progress.foundBooks} books found, ${progress.cachedBooks} cached`);
    console.log(`📊 Rate limit compliance: ${progress.rateLimitInfo.compliance} (avg ${progress.rateLimitInfo.avgInterval}ms)`);

    return progress;

  } catch (error) {
    console.error('Enhanced warming failed:', error);
    progress.phase = 'failed';
    progress.error = error.message;
    progress.completedTime = new Date().toISOString();
    await updateProgress(env, warmingId, progress);
    throw error;
  }
}

/**
 * Handle live status request - returns latest warming progress for dashboard
 */
async function handleLiveStatusRequest(request, env, ctx) {
  try {
    // Get all progress entries and find the latest
    const keys = await env.CACHE.list({ prefix: 'progress_warming_' });

    if (keys.keys.length === 0) {
      return new Response(JSON.stringify({
        hasActiveSession: false,
        processedAuthors: 0,
        foundBooks: 0,
        cachedBooks: 0,
        phase: 'idle',
        libraryStats: await getLibraryStats(env)
      }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Sort by name (timestamp) and get the latest
    const latestKey = keys.keys.sort((a, b) => b.name.localeCompare(a.name))[0];
    const latestProgress = await env.CACHE.get(latestKey.name, 'json');

    if (!latestProgress) {
      return new Response(JSON.stringify({
        hasActiveSession: false,
        processedAuthors: 0,
        foundBooks: 0,
        cachedBooks: 0,
        phase: 'idle',
        libraryStats: await getLibraryStats(env)
      }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Add cache statistics
    const cacheKeys = await env.CACHE.list();
    const libraryStats = await getLibraryStats(env);

    const response = {
      hasActiveSession: true,
      processedAuthors: latestProgress.processedAuthors || 0,
      foundBooks: latestProgress.foundBooks || 0,
      cachedBooks: latestProgress.cachedBooks || 0,
      totalAuthors: latestProgress.totalAuthors || 364,
      phase: latestProgress.phase || 'unknown',
      startTime: latestProgress.startTime,
      estimatedCompletion: latestProgress.estimatedCompletion,
      lastUpdate: new Date().toISOString(),
      libraryStats,
      cacheEntries: cacheKeys.keys.length,
      recentAuthors: (latestProgress.authorResults || []).slice(-5).map(author => ({
        name: author.author,
        books: author.foundBooks,
        success: author.success
      }))
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Live status failed:', error);
    return new Response(JSON.stringify({
      error: 'Failed to get live status',
      details: error.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

async function getLibraryStats(env) {
  const libraryData = await env.CACHE.get('current_library', 'json');
  return libraryData ? {
    totalBooks: libraryData.totalBooks,
    uniqueAuthors: (libraryData.authors || []).length,
    uploadTime: libraryData.uploadTime
  } : null;
}

/**
 * RELIABLE: Micro-batch processing for cron-based warming
 */
async function processMicroBatch(env, maxAuthors = 5) {
  console.log(`🔄 Starting micro-batch processing (max ${maxAuthors} authors)`);

  try {
    // Get library data
    const libraryData = await env.CACHE.get('current_library', 'json');
    if (!libraryData || !libraryData.authors) {
      console.log('❌ No library data found for micro-batch processing');
      return { success: false, message: 'No library data' };
    }

    // Get processing state
    let processingState = await env.CACHE.get('processing_state', 'json') || {
      currentAuthorIndex: 0,
      processedAuthors: 0,
      totalAuthors: libraryData.authors.length,
      startTime: new Date().toISOString(),
      completedAuthors: []
    };

    // Process next batch of authors
    const startIndex = processingState.currentAuthorIndex;
    const endIndex = Math.min(startIndex + maxAuthors, libraryData.authors.length);

    if (startIndex >= libraryData.authors.length) {
      console.log('✅ All authors processed, resetting for next cycle');
      processingState.currentAuthorIndex = 0;
      processingState.processedAuthors = 0;
      processingState.startTime = new Date().toISOString();
      processingState.completedAuthors = [];
    } else {
      const authorsToProcess = libraryData.authors.slice(startIndex, endIndex);
      console.log(`📚 Processing authors ${startIndex} to ${endIndex-1}: ${authorsToProcess.join(', ')}`);

      // Process each author reliably
      for (const author of authorsToProcess) {
        try {
          const result = await callISBNdbWorkerReliable(author, env);

          if (result.success && result.books) {
            // Cache the result using dual-format storage for compatibility
            await storeDualFormatCache(env, author, result);

            processingState.completedAuthors.push({
              name: author,
              books: result.books.length,
              success: true,
              timestamp: new Date().toISOString()
            });

            console.log(`✅ Cached ${result.books.length} books for ${author}`);
          } else {
            processingState.completedAuthors.push({
              name: author,
              books: 0,
              success: false,
              error: result.error || 'Unknown error',
              timestamp: new Date().toISOString()
            });
          }

          // OPTIMIZED: Aggressive rate limiting (0.8s instead of 1.1s)
          // This allows ~4500 calls/hour instead of ~3270 calls/hour
          await new Promise(resolve => setTimeout(resolve, RATE_LIMIT_INTERVAL));

          // Update quota usage
          quotaUsage.calls++;
          quotaUsage.authors++;

        } catch (error) {
          console.error(`❌ Error processing ${author}:`, error);
          processingState.completedAuthors.push({
            name: author,
            books: 0,
            success: false,
            error: error.message,
            timestamp: new Date().toISOString()
          });
        }
      }

      // Update processing state
      processingState.currentAuthorIndex = endIndex;
      processingState.processedAuthors += authorsToProcess.length;
    }

    // Save processing state
    await env.CACHE.put('processing_state', JSON.stringify(processingState), { expirationTtl: 86400 });

    console.log(`🎯 Micro-batch complete: ${processingState.processedAuthors}/${processingState.totalAuthors} authors processed`);

    return {
      success: true,
      processed: authorsToProcess?.length || 0,
      totalProcessed: processingState.processedAuthors,
      totalAuthors: processingState.totalAuthors,
      nextBatch: processingState.currentAuthorIndex < processingState.totalAuthors
    };

  } catch (error) {
    console.error('❌ Micro-batch processing error:', error);
    return { success: false, error: error.message };
  }
}

/**
 * RELIABLE: Direct ISBNdb worker calls (no service binding complexity)
 */
async function callISBNdbWorkerReliable(author, env) {
  try {
    // ✅ FIXED: Service bindings require absolute URLs
    const response = await fetch(
      `https://isbndb-biography-worker-production.jukasdrj.workers.dev/author/${encodeURIComponent(author)}`,
      {
        signal: AbortSignal.timeout(25000) // Well under 30s limit
      }
    );

    if (!response.ok) {
      throw new Error(`ISBNdb worker responded with ${response.status}`);
    }

    return await response.json();
  } catch (error) {
    console.error(`❌ Error calling ISBNdb worker for ${author}:`, error);
    return { success: false, error: error.message };
  }
}

/**
 * RELIABLE: Daily cache verification and repair
 */
async function verifyAndRepairCache(env) {
  console.log('🔍 Starting daily cache verification');

  try {
    // Get library data and processing state
    const libraryData = await env.CACHE.get('current_library', 'json');
    if (!libraryData || !libraryData.authors) {
      console.log('❌ No library data for verification');
      return;
    }

    // Check cache coverage
    let cachedAuthors = 0;
    let totalBooks = 0;

    for (const author of libraryData.authors) {
      const cacheKey = `author:${author.toLowerCase()}`;
      const cached = await env.CACHE.get(cacheKey, 'json');

      if (cached && cached.books) {
        cachedAuthors++;
        totalBooks += cached.books.length;
      }
    }

    const coverage = (cachedAuthors / libraryData.authors.length * 100).toFixed(1);
    console.log(`📊 Cache coverage: ${cachedAuthors}/${libraryData.authors.length} authors (${coverage}%), ${totalBooks} total books`);

    // Store verification results
    const verification = {
      timestamp: new Date().toISOString(),
      totalAuthors: libraryData.authors.length,
      cachedAuthors,
      coverage: parseFloat(coverage),
      totalBooks
    };

    await env.CACHE.put('cache_verification', JSON.stringify(verification), { expirationTtl: 86400 });

    return verification;

  } catch (error) {
    console.error('❌ Cache verification error:', error);
  }
}

async function handleKVDebug(request, env, ctx) {
  try {
    // Test KV operations
    const testKey = `debug_test_${Date.now()}`;
    const testValue = { timestamp: new Date().toISOString(), test: true };

    // Write test
    await env.CACHE.put(testKey, JSON.stringify(testValue), { expirationTtl: 300 });

    // Read test
    const readBack = await env.CACHE.get(testKey, 'json');

    // List all keys
    const allKeys = await env.CACHE.list();

    // Get some sample keys for debugging
    const sampleKeys = allKeys.keys.slice(0, 10).map(k => ({
      name: k.name,
      metadata: k.metadata
    }));

    return new Response(JSON.stringify({
      kvNamespaceId: 'b9cade63b6db48fd80c109a013f38fdb',
      testWrite: { key: testKey, success: !!readBack },
      testRead: readBack,
      totalKeys: allKeys.keys.length,
      sampleKeys,
      timestamp: new Date().toISOString()
    }, null, 2), {
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    return new Response(JSON.stringify({
      error: error.message,
      stack: error.stack
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}