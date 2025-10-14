/**
 * Bookshelf AI Worker - Production Deployment
 *
 * Exposes an API endpoint that accepts bookshelf images and uses Gemini 2.5 Flash
 * to identify books, extract titles/authors, and return normalized bounding boxes.
 *
 * Architecture: Standalone worker with optional RPC export for books-api-proxy integration
 */

// AI model configuration
const AI_MODEL = "gemini-2.5-flash-preview-05-20";
const USER_AGENT = 'BooksTracker/3.0.0 (nerd@ooheynerds.com) BookshelfAIWorker/1.0.0';

/**
 * RPC-compatible class for service binding integration
 */
export class BookshelfAIWorker {
  constructor(env) {
    this.env = env;
  }

  /**
   * Scans a bookshelf image and returns detected books with bounding boxes
   * @param {ArrayBuffer} imageData - Raw image data
   * @param {Object} options - Optional configuration
   * @returns {Promise<Object>} Scan results with books array
   */
  async scanBookshelf(imageData, options = {}) {
    const startTime = Date.now();

    try {
      console.log(`[BookshelfAI] Starting scan, image size: ${imageData.byteLength} bytes`);

      // Validate image size
      const maxSizeBytes = (this.env.MAX_IMAGE_SIZE_MB || 10) * 1024 * 1024;
      if (imageData.byteLength > maxSizeBytes) {
        throw new Error(`Image too large. Max ${this.env.MAX_IMAGE_SIZE_MB || 10}MB`);
      }

      // Get API key from secrets store
      console.log('[DEBUG] env.GEMINI_API_KEY type:', typeof this.env.GEMINI_API_KEY);
      console.log('[DEBUG] env keys:', Object.keys(this.env));

      const apiKey = await this.env.GEMINI_API_KEY.get();
      if (!apiKey) {
        throw new Error("GEMINI_API_KEY not configured in secrets store");
      }

      // Process with Gemini AI
      const result = await processImageWithAI(imageData, apiKey);

      // Enrich high-confidence detections via books-api-proxy
      const enrichmentStartTime = Date.now();
      const enrichedBooks = await enrichBooks(
        result.books,
        this.env,
        parseFloat(this.env.CONFIDENCE_THRESHOLD) || 0.7
      );
      const enrichmentTime = Date.now() - enrichmentStartTime;

      const processingTime = Date.now() - startTime;

      // Track analytics
      if (this.env.AI_ANALYTICS) {
        await this.env.AI_ANALYTICS.writeDataPoint({
          doubles: [processingTime, enrichmentTime, enrichedBooks.length],
          blobs: ['bookshelf_scan_with_enrichment', this.env.AI_MODEL || AI_MODEL],
          indexes: ['ai-scan-success']
        });
      }

      console.log(`[BookshelfAI] Scan completed: ${enrichedBooks.length} books (${enrichedBooks.filter(b => b.enrichment?.status === 'success').length} enriched) in ${processingTime}ms (enrichment: ${enrichmentTime}ms)`);

      return {
        success: true,
        books: enrichedBooks,
        metadata: {
          processingTime,
          enrichmentTime,
          detectedCount: enrichedBooks.length,
          readableCount: enrichedBooks.filter(b => b.title && b.author).length,
          enrichedCount: enrichedBooks.filter(b => b.enrichment?.status === 'success').length,
          model: this.env.AI_MODEL || AI_MODEL,
          timestamp: new Date().toISOString()
        }
      };

    } catch (error) {
      const processingTime = Date.now() - startTime;

      console.error(`[BookshelfAI] Scan failed:`, error);

      // Track failure analytics
      if (this.env.AI_ANALYTICS) {
        await this.env.AI_ANALYTICS.writeDataPoint({
          doubles: [processingTime, 0],
          blobs: ['bookshelf_scan_error', error.message],
          indexes: ['ai-scan-failure']
        });
      }

      throw error;
    }
  }
}

/**
 * Main worker fetch handler
 */
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Serve HTML testing interface on GET requests
    if (request.method === "GET" && url.pathname === "/") {
      return new Response(html, {
        headers: { "Content-Type": "text/html" }
      });
    }

    // Health check endpoint
    if (request.method === "GET" && url.pathname === "/health") {
      return Response.json({
        status: "healthy",
        model: env.AI_MODEL || AI_MODEL,
        timestamp: new Date().toISOString()
      });
    }

    // Process POST requests with image data
    if (request.method === "POST" && url.pathname === "/scan") {
      // Validate content type
      const contentType = request.headers.get("content-type") || "";
      if (!contentType.startsWith("image/")) {
        return Response.json(
          { error: "Please upload an image file (image/*)" },
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }

      try {
        // Get image data
        const imageData = await request.arrayBuffer();

        // Create worker instance and scan
        const worker = new BookshelfAIWorker(env);
        const result = await worker.scanBookshelf(imageData);

        return Response.json(result, {
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*" // Enable CORS for iOS app
          }
        });

      } catch (error) {
        console.error("[BookshelfAI] Request error:", error);
        return Response.json(
          {
            error: "Scan failed",
            details: error.message
          },
          {
            status: 500,
            headers: { "Content-Type": "application/json" }
          }
        );
      }
    }

    return Response.json(
      { error: "Not Found. Use GET / for test interface or POST /scan with image." },
      { status: 404 }
    );
  },
};

/**
 * Processes the image using the Gemini Vision API
 * @param {ArrayBuffer} image_data - The raw image data
 * @param {string} apiKey - The API key for the Gemini API
 * @returns {Promise<object>} The parsed JSON result from the AI model
 */
async function processImageWithAI(image_data, apiKey) {
  if (!apiKey) {
    throw new Error("GEMINI_API_KEY not configured");
  }

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${AI_MODEL}:generateContent?key=${apiKey}`;

  // Convert ArrayBuffer to Base64
  const image_base64 = arrayBufferToBase64(image_data);

  // AI prompt for book detection
  const system_prompt = `You are a book detection specialist. Analyze the provided image of a bookshelf. Your task is to identify every book spine visible.

For each book you identify, perform the following actions:
1. Extract the book's title.
2. Extract the author's name.
3. Determine the bounding box coordinates for the book's spine.
4. Provide a confidence score (from 0.0 to 1.0) indicating how certain you are about the extracted title and author. A score of 1.0 means absolute certainty, while a score below 0.5 indicates a guess.

Return your findings as a JSON object that strictly adheres to the provided schema.

If you can clearly identify a book's spine but the text is unreadable, you MUST still include it. In such cases, set 'title' and 'author' to null and the 'confidence' to 0.0.

Here is an example of a good detection:
{
  "title": "The Hitchhiker's Guide to the Galaxy",
  "author": "Douglas Adams",
  "confidence": 0.95,
  "boundingBox": { "x1": 0.1, "y1": 0.2, "x2": 0.15, "y2": 0.8 }
}

Here is an example of an unreadable book:
{
  "title": null,
  "author": null,
  "confidence": 0.0,
  "boundingBox": { "x1": 0.2, "y1": 0.3, "x2": 0.25, "y2": 0.9 }
}`;

  // JSON schema for structured output
  const schema = {
    type: "OBJECT",
    properties: {
      books: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          properties: {
            title: {
              type: "STRING",
              description: "The full title of the book.",
              nullable: true
            },
            author: {
              type: "STRING",
              description: "The full name of the author.",
              nullable: true
            },
            confidence: {
              type: "NUMBER",
              description: "Confidence score (0.0-1.0) for the extracted title/author."
            },
            boundingBox: {
              type: "OBJECT",
              description: "The normalized coordinates of the book spine in the image.",
              properties: {
                x1: { type: "NUMBER", description: "Top-left corner X coordinate (0-1)." },
                y1: { type: "NUMBER", description: "Top-left corner Y coordinate (0-1)." },
                x2: { type: "NUMBER", description: "Bottom-right corner X coordinate (0-1)." },
                y2: { type: "NUMBER", description: "Bottom-right corner Y coordinate (0-1)." },
              },
              required: ["x1", "y1", "x2", "y2"],
            },
          },
          required: ["boundingBox", "title", "author", "confidence"],
        },
      },
    },
    required: ["books"],
  };

  const payload = {
    contents: [
      {
        parts: [
          { text: system_prompt },
          {
            inlineData: {
              mimeType: "image/jpeg",
              data: image_base64,
            },
          },
        ],
      },
    ],
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: schema,
    },
  };

  // Call Gemini API with timeout
  const controller = new AbortController();
  const timeoutMs = 50000; // 50s timeout for large images
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "User-Agent": USER_AGENT
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Gemini API Error: ${response.status} ${response.statusText} - ${errorText}`);
    }

    const result = await response.json();

    const candidate = result.candidates?.[0];
    if (!candidate || !candidate.content?.parts?.[0]?.text) {
      throw new Error("Invalid response structure from Gemini API.");
    }

    // Parse the JSON response from Gemini
    return JSON.parse(candidate.content.parts[0].text);

  } finally {
    clearTimeout(timeout);
  }
}

/**
 * Utility to convert ArrayBuffer to Base64 string
 * @param {ArrayBuffer} buffer - The buffer to convert
 * @returns {string} The Base64 encoded string
 */
function arrayBufferToBase64(buffer) {
  let binary = '';
  const bytes = new Uint8Array(buffer);
  const len = bytes.byteLength;
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

/**
 * Enriches detected books by calling books-api-proxy via RPC
 * @param {Array} books - Array of detected books with title, author, confidence
 * @param {Object} env - Worker environment with BOOKS_API_PROXY binding
 * @param {number} confidenceThreshold - Minimum confidence to enrich (default: 0.7)
 * @returns {Promise<Array>} Books with enrichment data added
 */
async function enrichBooks(books, env, confidenceThreshold = 0.7) {
  // Filter high-confidence books for enrichment
  const booksToEnrich = books.filter(book =>
    book.confidence >= confidenceThreshold &&
    book.title &&
    book.author
  );

  console.log(`[Enrichment] ${booksToEnrich.length}/${books.length} books meet confidence threshold (${confidenceThreshold})`);

  if (booksToEnrich.length === 0) {
    // No books to enrich, return original array
    return books.map(book => ({
      ...book,
      enrichment: {
        status: 'skipped',
        reason: book.confidence < confidenceThreshold
          ? 'low_confidence'
          : 'missing_data'
      }
    }));
  }

  // Call books-api-proxy with batch request
  const enrichmentStartTime = Date.now();
  const enrichedResults = [];

  // Process each book with books-api-proxy /search/advanced endpoint
  for (const book of booksToEnrich) {
    try {
      // Construct search URL with title and author
      const searchURL = new URL('https://books-api-proxy.jukasdrj.workers.dev/search/advanced');
      searchURL.searchParams.set('title', book.title);
      searchURL.searchParams.set('author', book.author);

      // Call via service binding (RPC)
      const response = await env.BOOKS_API_PROXY.fetch(searchURL);

      if (!response.ok) {
        console.warn(`[Enrichment] Failed for "${book.title}": ${response.status}`);
        enrichedResults.push({
          ...book,
          enrichment: {
            status: 'failed',
            error: `API error: ${response.status}`
          }
        });
        continue;
      }

      const apiData = await response.json();

      // Extract first result from books-api-proxy response
      const firstResult = apiData.results?.[0];
      if (firstResult) {
        enrichedResults.push({
          ...book,
          enrichment: {
            status: 'success',
            isbn: firstResult.isbn13 || firstResult.isbn,
            coverUrl: firstResult.thumbnail,
            publicationYear: firstResult.year,
            publisher: firstResult.publisher,
            pageCount: firstResult.pages,
            subjects: firstResult.subjects || [],
            provider: apiData.provider || 'unknown',
            cachedResult: apiData.cached || false
          }
        });
      } else {
        // No results found
        enrichedResults.push({
          ...book,
          enrichment: {
            status: 'not_found',
            provider: apiData.provider || 'unknown'
          }
        });
      }

    } catch (error) {
      console.error(`[Enrichment] Error for "${book.title}":`, error);
      enrichedResults.push({
        ...book,
        enrichment: {
          status: 'error',
          error: error.message
        }
      });
    }
  }

  const enrichmentTime = Date.now() - enrichmentStartTime;
  console.log(`[Enrichment] Completed in ${enrichmentTime}ms: ${enrichedResults.filter(b => b.enrichment?.status === 'success').length} successful`);

  // Merge enriched results back with low-confidence books
  const enrichmentMap = new Map(
    enrichedResults.map(book => [book.title + '|' + book.author, book])
  );

  return books.map(book => {
    const key = book.title + '|' + book.author;
    return enrichmentMap.get(key) || {
      ...book,
      enrichment: {
        status: 'skipped',
        reason: 'low_confidence'
      }
    };
  });
}

// HTML testing interface
const html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>BooksTrack AI Bookshelf Scanner</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif; }
        .drop-zone { transition: all 0.2s ease-in-out; }
        .loader { border-top-color: #3b82f6; animation: spin 1s linear infinite; }
        @keyframes spin { to { transform: rotate(360deg); } }
    </style>
</head>
<body class="bg-gray-100 text-gray-800 flex items-center justify-center min-h-screen">
    <div class="container mx-auto p-4 md:p-8 max-w-4xl w-full">
        <div class="bg-white rounded-2xl shadow-xl p-6 md:p-8">
            <header class="text-center mb-6">
                <h1 class="text-3xl md:text-4xl font-bold text-gray-900">📚 BooksTrack AI Scanner</h1>
                <p class="text-gray-600 mt-2">Upload a bookshelf photo to identify books with AI</p>
                <p class="text-sm text-gray-500 mt-1">Powered by Gemini 2.5 Flash</p>
            </header>

            <main>
                <div id="upload-container">
                    <div id="drop-zone" class="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center cursor-pointer bg-gray-50 hover:bg-blue-50 hover:border-blue-400">
                        <input type="file" id="file-input" class="hidden" accept="image/*">
                        <svg class="mx-auto h-12 w-12 text-gray-400" stroke="currentColor" fill="none" viewBox="0 0 48 48">
                            <path d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                        </svg>
                        <p class="mt-4 text-gray-600">
                            <span class="font-semibold text-blue-600">Click to upload</span> or drag and drop
                        </p>
                        <p class="text-xs text-gray-500 mt-1">PNG, JPG up to 10MB</p>
                    </div>
                </div>

                <div id="image-preview-container" class="hidden mt-6 text-center">
                    <div class="relative inline-block">
                        <canvas id="image-canvas" class="rounded-lg shadow-md max-w-full h-auto"></canvas>
                        <div id="loader" class="loader ease-linear rounded-full border-4 border-t-4 border-gray-200 h-12 w-12 absolute" style="top: 50%; left: 50%; transform: translate(-50%, -50%); display: none;"></div>
                    </div>
                    <button id="scan-button" class="mt-4 w-full md:w-auto bg-blue-600 text-white font-bold py-3 px-6 rounded-lg hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition disabled:opacity-50">
                        🔍 Scan Bookshelf
                    </button>
                </div>

                <div id="results-container" class="hidden mt-8">
                    <h2 class="text-2xl font-bold text-center mb-4">Scan Results</h2>
                    <div id="stats" class="grid grid-cols-3 gap-4 mb-4">
                        <div class="bg-blue-50 p-4 rounded-lg text-center">
                            <div class="text-2xl font-bold text-blue-600" id="detected-count">0</div>
                            <div class="text-sm text-gray-600">Detected</div>
                        </div>
                        <div class="bg-green-50 p-4 rounded-lg text-center">
                            <div class="text-2xl font-bold text-green-600" id="readable-count">0</div>
                            <div class="text-sm text-gray-600">Readable</div>
                        </div>
                        <div class="bg-purple-50 p-4 rounded-lg text-center">
                            <div class="text-2xl font-bold text-purple-600" id="processing-time">0ms</div>
                            <div class="text-sm text-gray-600">Processing Time</div>
                        </div>
                    </div>
                    <div class="bg-gray-900 text-white font-mono text-sm p-4 rounded-lg overflow-x-auto max-h-96">
                        <pre id="json-output"></pre>
                    </div>
                </div>
            </main>
        </div>
    </div>

    <script>
        const dropZone = document.getElementById('drop-zone');
        const fileInput = document.getElementById('file-input');
        const uploadContainer = document.getElementById('upload-container');
        const imagePreviewContainer = document.getElementById('image-preview-container');
        const canvas = document.getElementById('image-canvas');
        const ctx = canvas.getContext('2d');
        const scanButton = document.getElementById('scan-button');
        const resultsContainer = document.getElementById('results-container');
        const jsonOutput = document.getElementById('json-output');
        const loader = document.getElementById('loader');

        let currentFile = null;

        // Event Listeners
        dropZone.addEventListener('click', () => fileInput.click());
        dropZone.addEventListener('dragover', (e) => {
            e.preventDefault();
            dropZone.classList.add('bg-blue-100', 'border-blue-400');
        });
        dropZone.addEventListener('dragleave', () => {
            dropZone.classList.remove('bg-blue-100', 'border-blue-400');
        });
        dropZone.addEventListener('drop', (e) => {
            e.preventDefault();
            dropZone.classList.remove('bg-blue-100', 'border-blue-400');
            const files = e.dataTransfer.files;
            if (files.length) handleFile(files[0]);
        });
        fileInput.addEventListener('change', (e) => {
            if (e.target.files.length) handleFile(e.target.files[0]);
        });
        scanButton.addEventListener('click', processImage);

        function handleFile(file) {
            if (!file.type.startsWith('image/')) {
                alert('Please select an image file.');
                return;
            }
            currentFile = file;

            const reader = new FileReader();
            reader.onload = (e) => {
                const img = new Image();
                img.onload = () => {
                    canvas.width = img.width;
                    canvas.height = img.height;
                    ctx.drawImage(img, 0, 0);
                    uploadContainer.classList.add('hidden');
                    imagePreviewContainer.classList.remove('hidden');
                    resultsContainer.classList.add('hidden');
                };
                img.src = e.target.result;
            };
            reader.readAsDataURL(file);
        }

        async function processImage() {
            if (!currentFile) return;

            setLoading(true);
            resultsContainer.classList.add('hidden');

            try {
                const response = await fetch('/scan', {
                    method: 'POST',
                    headers: { 'Content-Type': currentFile.type },
                    body: currentFile
                });

                if (!response.ok) {
                    const errorData = await response.json();
                    throw new Error(errorData.error || 'Failed to process image.');
                }

                const data = await response.json();
                displayResults(data);

            } catch (error) {
                console.error('Error:', error);
                alert('An error occurred: ' + error.message);
                redrawOriginalImage();
            } finally {
                setLoading(false);
            }
        }

        function displayResults(data) {
            // Update stats
            document.getElementById('detected-count').textContent = data.metadata.detectedCount;
            document.getElementById('readable-count').textContent = data.metadata.readableCount;
            document.getElementById('processing-time').textContent = data.metadata.processingTime + 'ms';

            // Show JSON
            jsonOutput.textContent = JSON.stringify(data, null, 2);
            resultsContainer.classList.remove('hidden');

            // Draw bounding boxes
            drawBoundingBoxes(data.books || []);
        }

        function drawBoundingBoxes(books) {
            redrawOriginalImage();

            books.forEach(book => {
                const { x1, y1, x2, y2 } = book.boundingBox;
                const isReadable = book.title && book.author;

                // Denormalize coordinates
                const rectX = x1 * canvas.width;
                const rectY = y1 * canvas.height;
                const rectWidth = (x2 - x1) * canvas.width;
                const rectHeight = (y2 - y1) * canvas.height;

                // Draw bounding box
                ctx.strokeStyle = isReadable ? 'rgba(34, 197, 94, 0.9)' : 'rgba(239, 68, 68, 0.9)';
                ctx.lineWidth = Math.max(2, canvas.width * 0.005);
                ctx.strokeRect(rectX, rectY, rectWidth, rectHeight);

                // Draw label
                const text = isReadable ? \`\${book.title} - \${book.author}\` : 'Unreadable';
                const fontSize = Math.max(12, canvas.width * 0.015);
                ctx.font = \`bold \${fontSize}px sans-serif\`;

                const textMetrics = ctx.measureText(text);
                const textBgX = rectX;
                const textBgY = rectY - (fontSize + 8);
                const textBgWidth = textMetrics.width + 10;
                const textBgHeight = fontSize + 8;

                // Draw text background
                ctx.fillStyle = isReadable ? 'rgba(34, 197, 94, 0.9)' : 'rgba(239, 68, 68, 0.9)';
                ctx.fillRect(textBgX, textBgY, textBgWidth, textBgHeight);

                // Draw text
                ctx.fillStyle = '#FFFFFF';
                ctx.fillText(text, textBgX + 5, textBgY + fontSize);
            });
        }

        function redrawOriginalImage() {
            const img = new Image();
            img.onload = () => ctx.drawImage(img, 0, 0);
            img.src = URL.createObjectURL(currentFile);
        }

        function setLoading(isLoading) {
            scanButton.disabled = isLoading;
            loader.style.display = isLoading ? 'block' : 'none';
        }
    </script>
</body>
</html>
`;
