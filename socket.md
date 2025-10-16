**WebSockets are an appropriate choice** for updating the BooksTracker application's communication structure, especially for asynchronous processes that currently rely on periodic polling. Implementing this would dramatically improve the user experience for long-running jobs like CSV import enrichment and bookshelf scanning.

---

## 💡 Why WebSockets Are the Right Choice

| Feature | Current Polling/Notification System | Proposed WebSockets System |
| :--- | :--- | :--- |
| **Real-Time Updates** | Delayed (updates only when polled, typically every 0.1s to 2s) | **Instant** (server pushes updates immediately) |
| **Server Overhead** | High (client makes repeated HTTP requests, causing high traffic and I/O load) | **Low** (a single persistent connection per user/job) |
| **Client Overhead** | High (requires complex local logic, like the `Task + Task.sleep` pattern used in `PollingUtility.swift` and logic in `SyncCoordinator.swift`, to manage interval checking) | **Low** (simply opens one connection and listens for data) |
| **User Experience** | Degraded (can feel choppy or slow due to polling delay) | **Fluid and Live** (progress bars update smoothly) |
| **Architecture Fit** | Excellent (The project already lists this as a future enhancement for advanced features like the Bookshelf Scanner) |

---

## 🛠️ How to Implement WebSockets

The transition moves the communication model from a **Client-Driven (Polling)** approach to a **Server-Driven (Push)** model.

### 1. Backend: Cloudflare Workers

You would need to introduce a new WebSocket handling endpoint (e.g., `/ws/progress`) and use Cloudflare's WebSocket support.

| Component | Action |
| :--- | :--- |
| **New Endpoint** | Create a new endpoint (e.g., `GET /ws/progress`) on a relevant worker, such as `books-api-proxy` or a new dedicated worker. This endpoint must handle the **WebSocket upgrade handshake** from the client. |
| **Connection Storage** | When the handshake is successful, the worker must store the resulting `WebSocket` object (e.g., in a Durable Object or a persistent Map, keyed by a `jobId` or user ID). |
| **Job Integration** | Modify the core background job logic (e.g., inside the server-side component of the **Bookshelf Scanner's asynchronous process** or the **EnrichmentQueue** if running on the worker). Instead of updating a KV key for the client to poll, the job sends a JSON message directly through the stored WebSocket connection. |
| **Teardown** | Implement logic to close the WebSocket connection and delete the stored reference immediately upon job completion or failure, as well as when the client disconnects. |

### 2. Frontend: iOS Application (SwiftUI/Swift Concurrency)

You will replace the existing polling utility with Swift's native WebSocket API:

| Component | Action |
| :--- | :--- |
| **Remove Polling Logic** | Eliminate the custom polling implementations that use constructs like `Task.sleep` and the `check` closures defined in `PollingUtility.swift`. |
| **Establish Connection** | Use **`URLSessionWebSocketTask`** to establish a secure connection (`wss://`) immediately after initiating an asynchronous job (e.g., after the client posts the CSV file). |
| **Listen for Push Data** | The client's `Task` would enter a loop to await and process incoming messages (typically JSON strings) from the WebSocket. These messages contain the real-time progress data (e.g., `{ progress: 0.5, status: "Enriching Metadata" }`). |
| **Update UI Reactively** | Incoming progress data should be safely handed off to update the **`@Observable` state models** on the **`@MainActor`** for immediate UI reflection, providing a very smooth user experience. |
| **Error Handling** | Implement robust logic to reconnect on unexpected closure and cleanly close the connection when the associated view disappears or the job is finished. |

---

## ⚠️ Key Architectural Consideration

The current backend architecture relies on **Service Bindings (RPC)** for fast worker-to-worker communication (e.g., `books-api-proxy` calling other workers). You must ensure that the new WebSocket service respects this architectural pattern and does not introduce latency by making direct external API calls. The WebSocket connection handles the **Client $\leftrightarrow$ Worker** communication, while **Worker $\leftrightarrow$ Worker** communication should remain over Service Bindings.