# Northstar University Admissions Portal

A responsive admissions-portal demo with a general-purpose AI chat assistant powered by the local Ollama model `qwen2.5:3B`.

## Requirements

- Windows PowerShell
- Ollama installed and running
- The `qwen2.5:3B` model available in Ollama

The server uses built-in Windows PowerShell and .NET libraries; no packages or Node.js are needed. It serves the web app and proxies chat requests to the local Ollama API, so the browser never connects directly to the model service.

## Run on Windows

1. Open PowerShell in this folder.
2. Start the portal:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\server.ps1
   ```

3. Open [http://localhost:8000](http://localhost:8000).
4. Ensure Ollama is running. The page checks the local model connection and shows its status in the chat panel.

The default model is `qwen2.5:3B`, and the default Ollama URL is `http://127.0.0.1:11434`. Override them with `OLLAMA_MODEL`, `OLLAMA_URL`, or `PORT` environment variables if needed.

## Demo details

- Nova can answer general questions as well as questions about the portal.
- The university, programs, priority date, statistics, and application form are illustrative demo content.
- The form saves entries only in the current browser's local storage. It does not create or submit a real university application.
- Chat messages are sent to the local Ollama service through the Python server.
