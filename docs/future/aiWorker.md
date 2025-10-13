/**
 * Welcome to your AI Book Scanner Worker!
 *
 * This worker exposes an API endpoint that accepts an image of a bookshelf
 * and uses a multi-modal AI model (Gemini) to identify books, extract their
 * titles and authors, and return their bounding boxes.
 *
 * It's designed to be deployed directly to your Cloudflare account.
 */

// The AI model to use for vision and text extraction.
const AI_MODEL = "gemini-2.5-flash-preview-05-20";

export default {
  async fetch(request, env, ctx) {
    // We'll serve the HTML testing interface on GET requests
    if (request.method === "GET") {
      return new Response(html, { headers: { "Content-Type": "text/html" } });
    }

    // We expect a POST request with the image data for processing
    if (request.method === "POST") {
      // Check for content type to ensure we have an image
      const contentType = request.headers.get("content-type") || "";
      if (!contentType.startsWith("image/")) {
        return new Response(JSON.stringify({ error: "Please upload an image file." }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
      }

      // Get the image data as a Buffer/ArrayBuffer
      const image_data = await request.arrayBuffer();

      try {
        const result = await processImageWithAI(image_data, env.GEMINI_API_KEY);
        return new Response(JSON.stringify(result, null, 2), {
          headers: { "Content-Type": "application/json" },
        });
      } catch (e) {
        console.error(e);
        return new Response(JSON.stringify({ error: e.message }), {
          status: 500,
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    return new Response("Not Found", { status: 404 });
  },
};

/**
 * Processes the image using the Gemini Vision API.
 * @param {ArrayBuffer} image_data The raw image data.
 * @param {string} apiKey The API key for the Gemini API.
 * @returns {Promise<object>} The parsed JSON result from the AI model.
 */
async function processImageWithAI(image_data, apiKey) {
  // The API key is an empty string by default. 
  // Canvas will automatically provide it at runtime.
  // If you want to use a model other than gemini-2.5-flash-preview-05-20,
  // you may need to provide an API key here.
  const key = apiKey || "";
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${AI_MODEL}:generateContent?key=${key}`;

  // Convert ArrayBuffer to Base64
  const image_base64 = arrayBufferToBase64(image_data);

  // This is the prompt that instructs the AI on what to do.
  const system_prompt = `You are a book detection specialist. Analyze the provided image of a bookshelf. Your task is to identify every book spine visible.

For each book you identify, perform the following actions:
1.  Extract the book's title.
2.  Extract the author's name.
3.  Determine the bounding box coordinates for the book's spine.

Return your findings as a JSON object that strictly adheres to the provided schema.

If you can clearly identify a book's spine and determine its bounding box, but the text is blurred, unreadable, or obscured, you MUST still include it in the result. In such cases, set the 'title' and 'author' fields to null. Do not omit any identifiable book spine.`;

  // This schema enforces the JSON structure for the AI's response.
  const schema = {
    type: "OBJECT",
    properties: {
      books: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          properties: {
            title: { type: ["STRING", "NULL"], description: "The full title of the book." },
            author: { type: ["STRING", "NULL"], description: "The full name of the author." },
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
          required: ["boundingBox", "title", "author"],
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
              mimeType: "image/jpeg", // Assuming jpeg, but the browser will send correct type
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

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
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

  // The response is a string of JSON, so we need to parse it.
  return JSON.parse(candidate.content.parts[0].text);
}


/**
 * Utility to convert ArrayBuffer to Base64 string.
 * @param {ArrayBuffer} buffer The buffer to convert.
 * @returns {string} The Base64 encoded string.
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


// A simple HTML page to serve as a testing UI for the worker.
const html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Bookshelf Scanner</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { font-family: 'Inter', sans-serif; }
        .drop-zone { transition: background-color 0.2s ease-in-out; }
        .loader { border-top-color: #3498db; animation: spin 1s linear infinite; }
        @keyframes spin { to { transform: rotate(360deg); } }
    </style>
</head>
<body class="bg-gray-100 text-gray-800 flex items-center justify-center min-h-screen">
    <div class="container mx-auto p-4 md:p-8 max-w-4xl w-full">
        <div class="bg-white rounded-2xl shadow-xl p-6 md:p-8">
            <header class="text-center mb-6">
                <h1 class="text-3xl md:text-4xl font-bold text-gray-900">AI Bookshelf Scanner</h1>
                <p class="text-gray-600 mt-2">Upload a picture of your bookshelf to identify books.</p>
            </header>

            <main>
                <div id="upload-container">
                    <div id="drop-zone" class="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center cursor-pointer bg-gray-50 hover:bg-gray-200">
                        <input type="file" id="file-input" class="hidden" accept="image/*">
                        <svg class="mx-auto h-12 w-12 text-gray-400" stroke="currentColor" fill="none" viewBox="0 0 48 48" aria-hidden="true">
                            <path d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                        </svg>
                        <p class="mt-4 text-gray-600">
                            <span class="font-semibold text-indigo-600">Click to upload</span> or drag and drop
                        </p>
                        <p class="text-xs text-gray-500 mt-1">PNG, JPG, GIF up to 10MB</p>
                    </div>
                </div>

                <div id="image-preview-container" class="hidden mt-6 text-center">
                     <div class="relative inline-block">
                        <canvas id="image-canvas" class="rounded-lg shadow-md max-w-full h-auto"></canvas>
                        <div id="loader" class="loader ease-linear rounded-full border-4 border-t-4 border-gray-200 h-12 w-12 absolute" style="top: 50%; left: 50%; transform: translate(-50%, -50%); display: none;"></div>
                    </div>
                    <button id="scan-button" class="mt-4 w-full md:w-auto bg-indigo-600 text-white font-bold py-3 px-6 rounded-lg hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition disabled:opacity-50">
                        Scan Bookshelf
                    </button>
                </div>

                <div id="results-container" class="hidden mt-8">
                    <h2 class="text-2xl font-bold text-center mb-4">Scan Results</h2>
                    <div class="bg-gray-900 text-white font-mono text-sm p-4 rounded-lg overflow-x-auto">
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

        // --- Event Listeners ---
        dropZone.addEventListener('click', () => fileInput.click());
        dropZone.addEventListener('dragover', (e) => {
            e.preventDefault();
            dropZone.classList.add('bg-indigo-100', 'border-indigo-400');
        });
        dropZone.addEventListener('dragleave', () => {
            dropZone.classList.remove('bg-indigo-100', 'border-indigo-400');
        });
        dropZone.addEventListener('drop', (e) => {
            e.preventDefault();
            dropZone.classList.remove('bg-indigo-100', 'border-indigo-400');
            const files = e.dataTransfer.files;
            if (files.length) {
                handleFile(files[0]);
            }
        });
        fileInput.addEventListener('change', (e) => {
            if (e.target.files.length) {
                handleFile(e.target.files[0]);
            }
        });
        scanButton.addEventListener('click', processImage);

        // --- Functions ---
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
                    jsonOutput.textContent = '';
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
                const response = await fetch(window.location.href, {
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
                // Redraw original image without boxes on error
                 const img = new Image();
                 img.onload = () => {
                    ctx.drawImage(img, 0, 0);
                 }
                 img.src = URL.createObjectURL(currentFile);

            } finally {
                setLoading(false);
            }
        }

        function displayResults(data) {
            jsonOutput.textContent = JSON.stringify(data, null, 2);
            resultsContainer.classList.remove('hidden');
            drawBoundingBoxes(data.books || []);
        }

        function drawBoundingBoxes(books) {
            // Redraw image to clear previous boxes
            const img = new Image();
            img.onload = () => {
                ctx.drawImage(img, 0, 0);

                books.forEach(book => {
                    const { x1, y1, x2, y2 } = book.boundingBox;
                    const isReadable = book.title && book.author;

                    // Denormalize coordinates
                    const rectX = x1 * canvas.width;
                    const rectY = y1 * canvas.height;
                    const rectWidth = (x2 - x1) * canvas.width;
                    const rectHeight = (y2 - y1) * canvas.height;
                    
                    // Draw bounding box
                    ctx.strokeStyle = isReadable ? 'rgba(52, 211, 153, 0.9)' : 'rgba(239, 68, 68, 0.9)'; // Green for readable, Red for not
                    ctx.lineWidth = Math.max(2, canvas.width * 0.005);
                    ctx.strokeRect(rectX, rectY, rectWidth, rectHeight);

                    // Prepare text
                    const text = isReadable ? \`\${book.title} - \${book.author}\` : 'Unreadable';
                    const fontSize = Math.max(12, canvas.width * 0.015);
                    ctx.font = \`bold \${fontSize}px sans-serif\`;
                    
                    const textMetrics = ctx.measureText(text);
                    const textBgX = rectX;
                    const textBgY = rectY - (fontSize + 8); // Position above the box
                    const textBgWidth = textMetrics.width + 10;
                    const textBgHeight = fontSize + 8;
                    
                    // Draw text background
                    ctx.fillStyle = isReadable ? 'rgba(52, 211, 153, 0.9)' : 'rgba(239, 68, 68, 0.9)';
                    ctx.fillRect(textBgX, textBgY, textBgWidth, textBgHeight);

                    // Draw text
                    ctx.fillStyle = '#FFFFFF';
                    ctx.fillText(text, textBgX + 5, textBgY + fontSize);
                });
            };
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
