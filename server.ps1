$ErrorActionPreference = "Stop"

$Port = if ($env:PORT) { [int]$env:PORT } else { 8000 }
$OllamaUrl = if ($env:OLLAMA_URL) { $env:OLLAMA_URL.TrimEnd("/") } else { "http://127.0.0.1:11434" }
$OllamaModel = if ($env:OLLAMA_MODEL) { $env:OLLAMA_MODEL } else { "qwen2.5:3B" }
$MaxRequestBytes = 64000
$Utf8 = [System.Text.Encoding]::UTF8
$StaticFiles = @{
    "/" = @{ File = "index.html"; Type = "text/html; charset=utf-8" }
    "/index.html" = @{ File = "index.html"; Type = "text/html; charset=utf-8" }
    "/styles.css" = @{ File = "styles.css"; Type = "text/css; charset=utf-8" }
    "/app.js" = @{ File = "app.js"; Type = "text/javascript; charset=utf-8" }
}
$SystemPrompt = @"
You are Nova, the helpful AI assistant inside the Northstar University admissions portal.
Answer the user's actual question directly and naturally, including questions unrelated to admissions or this website. You are a general-purpose assistant, not a website-only FAQ bot.
When a question is about Northstar University or the portal, use this verified context:
- Northstar University is a fictional example university. Do not claim to know real institutional policies, accreditation, or deadlines beyond the information below.
- The portal offers program information, an application checklist, and a way to start an application.
- The example application checklist is: create an account, choose a program, submit academic records, and review your application.
- The example priority application date shown on the page is March 15. It is illustrative, not a real admissions deadline.
If you do not know a current fact, say so plainly rather than inventing it. Be thoughtful and clear; use concise formatting when it helps.
"@

function Write-JsonResponse {
    param(
        [System.Net.HttpListenerContext]$Context,
        [int]$StatusCode,
        [object]$Payload
    )

    $body = $Utf8.GetBytes(($Payload | ConvertTo-Json -Compress -Depth 8))
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = "application/json; charset=utf-8"
    $Context.Response.ContentLength64 = $body.Length
    $Context.Response.Headers["Cache-Control"] = "no-store"
    $Context.Response.OutputStream.Write($body, 0, $body.Length)
    $Context.Response.Close()
}

function Handle-Request {
    param([System.Net.HttpListenerContext]$Context)

    $path = $Context.Request.Url.AbsolutePath
    if ($Context.Request.HttpMethod -eq "GET" -and $path -eq "/api/health") {
        try {
            $tags = Invoke-RestMethod -Uri "$OllamaUrl/api/tags" -TimeoutSec 4
            $availableModels = @($tags.models | ForEach-Object { $_.name })
            Write-JsonResponse -Context $Context -StatusCode 200 -Payload @{
                ollama = $true
                model = $OllamaModel
                modelAvailable = ($availableModels -contains $OllamaModel)
                availableModels = $availableModels
            }
        }
        catch {
            Write-JsonResponse -Context $Context -StatusCode 200 -Payload @{
                ollama = $false
                model = $OllamaModel
                modelAvailable = $false
                error = $_.Exception.Message
            }
        }
        return
    }

    if ($Context.Request.HttpMethod -eq "POST" -and $path -eq "/api/chat") {
        if ($Context.Request.ContentLength64 -lt 1 -or $Context.Request.ContentLength64 -gt $MaxRequestBytes) {
            Write-JsonResponse -Context $Context -StatusCode 413 -Payload @{ error = "The chat request is empty or too large." }
            return
        }

        try {
            $reader = [System.IO.StreamReader]::new($Context.Request.InputStream, $Utf8)
            $inputJson = $reader.ReadToEnd()
            $reader.Dispose()
            $payload = $inputJson | ConvertFrom-Json
        }
        catch {
            Write-JsonResponse -Context $Context -StatusCode 400 -Payload @{ error = "The chat request must contain valid JSON." }
            return
        }

        $messages = @($payload.messages)
        if (-not $payload -or $messages.Count -lt 1 -or $messages.Count -gt 24) {
            Write-JsonResponse -Context $Context -StatusCode 400 -Payload @{ error = "Provide between 1 and 24 chat messages." }
            return
        }

        $safeMessages = [System.Collections.Generic.List[object]]::new()
        $safeMessages.Add(@{ role = "system"; content = $SystemPrompt })
        foreach ($message in $messages) {
            if ($message.role -notin @("user", "assistant") -or [string]::IsNullOrWhiteSpace([string]$message.content)) {
                Write-JsonResponse -Context $Context -StatusCode 400 -Payload @{
                    error = "Each chat message must have a valid role and non-empty content."
                }
                return
            }
            $content = [string]$message.content
            if ($content.Length -gt 8000) {
                $content = $content.Substring(0, 8000)
            }
            $safeMessages.Add(@{ role = [string]$message.role; content = $content })
        }

        try {
            $ollamaPayload = @{
                model = $OllamaModel
                messages = @($safeMessages.ToArray())
                stream = $false
                options = @{ temperature = 0.7 }
            } | ConvertTo-Json -Compress -Depth 8
            $result = Invoke-RestMethod -Uri "$OllamaUrl/api/chat" -Method Post `
                -ContentType "application/json; charset=utf-8" -Body $ollamaPayload -TimeoutSec 180
        }
        catch {
            Write-JsonResponse -Context $Context -StatusCode 503 -Payload @{
                error = "Could not get a reply from Ollama at $OllamaUrl. Make sure Ollama is running and the model is available. Details: $($_.Exception.Message)"
            }
            return
        }

        $answer = [string]$result.message.content
        if ([string]::IsNullOrWhiteSpace($answer)) {
            Write-JsonResponse -Context $Context -StatusCode 502 -Payload @{ error = "Ollama returned an empty answer." }
            return
        }
        Write-JsonResponse -Context $Context -StatusCode 200 -Payload @{ reply = $answer; model = $OllamaModel }
        return
    }

    if ($Context.Request.HttpMethod -eq "GET" -and $StaticFiles.ContainsKey($path)) {
        $file = $StaticFiles[$path]
        $filePath = Join-Path $PSScriptRoot $file.File
        $body = [System.IO.File]::ReadAllBytes($filePath)
        $Context.Response.StatusCode = 200
        $Context.Response.ContentType = $file.Type
        $Context.Response.ContentLength64 = $body.Length
        $Context.Response.OutputStream.Write($body, 0, $body.Length)
        $Context.Response.Close()
        return
    }

    Write-JsonResponse -Context $Context -StatusCode 404 -Payload @{ error = "Not found." }
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
try {
    $listener.Start()
    Write-Host "Northstar admissions portal: http://localhost:$Port"
    Write-Host "Ollama model: $OllamaModel at $OllamaUrl"
    Write-Host "Press Ctrl+C to stop the portal."
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            Handle-Request -Context $context
        }
        catch {
            Write-Warning "Request failed: $($_.Exception.Message)"
            if ($context.Response.OutputStream.CanWrite) {
                $context.Response.Abort()
            }
        }
    }
}
finally {
    $listener.Close()
}
