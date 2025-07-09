# Real-time Monitoring Dashboard Implementation Plan

This document outlines the steps to build a real-time, web-based monitoring dashboard for the Anagram Game server.

## Guiding Principles

- **API-Driven:** The dashboard will be a pure frontend application. It will not have its own database or backend logic.
- **Real-time:** All data will be streamed from the existing Node.js server to the dashboard via WebSockets.
- **Non-Intrusive:** The monitoring system will be isolated in its own service on the backend and a separate frontend application, ensuring it doesn't interfere with the core game logic.

---

## Phase 1: Backend Instrumentation

The goal of this phase is to instrument the Node.js server to collect and broadcast all relevant activity over a dedicated WebSocket channel.

### Step 1.1: Create the Monitoring Service
- **Action:** Create a new file at `server/services/monitoringService.js`.
- **Purpose:** This file will contain all logic for the monitoring system. It will initialize a dedicated `socket.io` namespace called `/monitoring` to keep this communication channel separate from the main game's WebSocket traffic.

### Step 1.2: Integrate the Service into `server.js`
- **Action:** In `server/server.js`, `require` and initialize the monitoring service. It will be passed the main `http` server instance to attach the `socket.io` listener.

### Step 1.3: Instrument Key Server Events
- **Action:** Add hooks into the existing application logic to send data to the `monitoringService`. The service will then broadcast this data to all connected dashboard clients.
- **Events to Capture:**
    - **API Requests:** Create a new middleware to log the method, path, status code, and response time of every API request.
    - **Player Lifecycle:** Hook into player registration (`DatabasePlayer.createPlayer`) and socket `disconnect` events to track when users join and leave.
    - **Database Statistics:** Create a `setInterval` within the monitoring service to periodically fetch and broadcast database connection pool statistics from the existing `getDbStats()` function.
    - **Game Logic:** Instrument key game actions like phrase completion, skips, and hint usage.
    - **Critical Errors:** Hook into the application's global error handler to broadcast any uncaught exceptions or critical failures immediately.

### Step 1.4: Backend Verification
- **Action:** Before starting frontend work, we will use a command-line WebSocket client (like `wscat`) to connect to the `/monitoring` endpoint and verify that the backend is correctly broadcasting events.

---

## Phase 2: Frontend Dashboard Implementation

The goal of this phase is to build the web interface that will connect to the backend and visualize the data stream.

### Step 2.1: Set Up the React Project
- **Action:** Create a new directory at the project root named `monitoring-dashboard`.
- **Tooling:** Use `npx create-react-app` to scaffold a new React project within this directory.
- **Dependencies:** Install necessary libraries: `socket.io-client` for WebSocket communication, and `chart.js` / `react-chartjs-2` for data visualization.

### Step 2.2: Establish WebSocket Connection
- **Action:** Create a utility module within the React app to manage the `socket.io` connection to the server's `/monitoring` namespace. The main `App` component will establish the connection when it mounts.

### Step 2.3: Build UI Components
- **Action:** Develop a set of modular React components, each responsible for displaying a specific piece of information.
- **Component Breakdown:**
    - `LiveLogViewer`: Displays a real-time, auto-scrolling list of all events received from the server.
    - `OnlinePlayersList`: Shows a list of all currently active players, updating as they join and leave.
    - `PerformanceGraphs`: Contains charts visualizing key metrics like database connections, API response times, and event loop latency.
    - `AlertsPanel`: A dedicated area at the top of the dashboard to prominently display critical errors or warnings.

### Step 2.4: Assemble the Main Dashboard View
- **Action:** Create a primary `Dashboard` component that arranges all the individual UI components into a clear and organized grid-based layout.

--- 