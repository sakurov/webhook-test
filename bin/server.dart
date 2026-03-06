import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

// --- Persistence ---

const _dbPath = 'webhooks_db.json';

void _saveEvents() {
  try {
    final file = File(_dbPath);
    final json = jsonEncode(_events.map((e) => e.toJson()).toList());
    file.writeAsStringSync(json);
  } catch (e) {
    print('Failed to save events: $e');
  }
}

void _loadEvents() {
  try {
    final file = File(_dbPath);
    if (file.existsSync()) {
      final content = file.readAsStringSync();
      final List<dynamic> json = jsonDecode(content);
      _events.clear();
      _events.addAll(json.map((j) => WebhookEvent.fromJson(j)));
      print('Loaded ${_events.length} events from database.');
    }
  } catch (e) {
    print('Failed to load events: $e');
  }
}

// --- Models ---

class WebhookEvent {
  final DateTime timestamp;
  final String method;
  final String path;
  final Map<String, String> queryParams;
  final Map<String, String> headers;
  final String body;
  final String sourceIp;

  WebhookEvent({
    required this.timestamp,
    required this.method,
    required this.path,
    required this.queryParams,
    required this.headers,
    required this.body,
    required this.sourceIp,
  });

  factory WebhookEvent.fromJson(Map<String, dynamic> json) {
    return WebhookEvent(
      timestamp: DateTime.parse(json['timestamp']),
      method: json['method'],
      path: json['path'],
      queryParams: Map<String, String>.from(json['queryParams'] ?? {}),
      headers: Map<String, String>.from(json['headers'] ?? {}),
      body: json['body'],
      sourceIp: json['sourceIp'],
    );
  }

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'method': method,
    'path': path,
    'queryParams': queryParams,
    'headers': headers,
    'body': body,
    'sourceIp': sourceIp,
  };
}

// --- Logic ---

final List<WebhookEvent> _events = [];

// --- Handlers ---

final _router = Router()
  ..get('/', _uiHandler)
  ..get('/api/events', _eventsHandler)
  ..all('/webhook', _webhookHandler)
  ..all('/webhook/<any|.*>', _webhookHandler) // catch all subpaths
  ..post('/api/clear', _clearHandler);

Future<Response> _uiHandler(Request req) async {
  return Response.ok(_getHtmlUi(), headers: {'Content-Type': 'text/html'});
}

Response _eventsHandler(Request req) {
  return Response.ok(
    jsonEncode(_events.map((e) => e.toJson()).toList()),
    headers: {'Content-Type': 'application/json'},
  );
}

Future<Response> _webhookHandler(Request req) async {
  final body = await req.readAsString();
  final event = WebhookEvent(
    timestamp: DateTime.now(),
    method: req.method,
    path: req.requestedUri.path,
    queryParams: req.requestedUri.queryParameters,
    headers: req.headers,
    body: body,
    sourceIp: req.context['shelf.io.connection_info'] != null
        ? (req.context['shelf.io.connection_info'] as HttpConnectionInfo)
              .remoteAddress
              .address
        : 'unknown',
  );

  _events.insert(0, event);
  if (_events.length > 50) _events.removeLast();

  _saveEvents();

  print('Received webhook: ${req.method} ${req.url}');

  return Response.ok(
    jsonEncode({'status': 'ok', 'received': true}),
    headers: {'Content-Type': 'application/json'},
  );
}

Response _clearHandler(Request req) {
  _events.clear();
  _saveEvents();
  return Response.ok(
    jsonEncode({'status': 'cleared'}),
    headers: {'Content-Type': 'application/json'},
  );
}

// --- Main ---

void main(List<String> args) async {
  _loadEvents();

  final ip = InternetAddress.anyIPv4;
  final port = int.parse(Platform.environment['PORT'] ?? '8080');

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_router.call);

  final server = await serve(handler, ip, port);
  print('--- Webhook Receiver ---');
  print('UI Dashboard:  http://localhost:${server.port}/');
  print('Webhook URL:   http://localhost:${server.port}/webhook');
  print('-------------------------');
}

// --- UI Template ---

String _getHtmlUi() {
  return '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Webhook Receiver Dashboard</title>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg: #0f172a;
            --card: #1e293b;
            --accent: #38bdf8;
            --text: #f8fafc;
            --subtext: #94a3b8;
            --code-bg: #000000;
            --header-key: #ec4899;
            --header-val: #10b981;
        }
        /* --- Beautiful Scrollbars --- */
        ::-webkit-scrollbar {
            width: 8px;
            height: 8px;
        }
        ::-webkit-scrollbar-track {
            background: rgba(15, 23, 42, 0.1);
            border-radius: 10px;
        }
        ::-webkit-scrollbar-thumb {
            background: #334155;
            border-radius: 10px;
            border: 2px solid var(--card);
        }
        ::-webkit-scrollbar-thumb:hover {
            background: var(--accent);
        }

        body {
            font-family: 'Outfit', sans-serif;
            background: var(--bg);
            color: var(--text);
            margin: 0;
            padding: 2rem;
            display: flex;
            flex-direction: column;
            align-items: center;
            overflow-x: hidden; /* Fix bug 2: Prevent global horizontal scroll */
        }
        .container {
            width: 100%;
            max-width: 1000px;
            box-sizing: border-box;
        }
        header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 2rem;
            width: 100%;
        }
        h1 { margin: 0; font-weight: 600; color: var(--accent); letter-spacing: -1px; }
        .controls { display: flex; gap: 1rem; }
        button {
            background: var(--card);
            color: var(--text);
            border: 1px solid #334155;
            padding: 0.6rem 1.2rem;
            border-radius: 10px;
            cursor: pointer;
            font-family: 'Outfit', sans-serif;
            font-weight: 500;
            transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
        }
        button:hover {
            border-color: var(--accent);
            color: var(--accent);
            background: rgba(56, 189, 248, 0.05);
            transform: translateY(-1px);
        }
        .empty-state {
            background: var(--card);
            padding: 4rem;
            border-radius: 20px;
            text-align: center;
            color: var(--subtext);
            border: 2px dashed #334155;
        }
        .event-list { display: grid; gap: 1.5rem; width: 100%; }
        .event-card {
            background: var(--card);
            border-radius: 20px;
            padding: 1.5rem;
            border: 1px solid #334155;
            box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
            transition: border-color 0.2s;
            max-width: 100%; /* Fix bug 2: Ensure card stays in container */
            box-sizing: border-box;
            overflow: hidden;
        }
        .event-card:hover { border-color: var(--accent); }
        .event-meta {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 1.5rem;
        }
        .path-group { display: flex; align-items: center; gap: 0.75rem; }
        .method {
            background: var(--accent);
            color: var(--bg);
            padding: 0.2rem 0.6rem;
            border-radius: 6px;
            font-weight: 800;
            font-size: 0.75rem;
            text-transform: uppercase;
        }
        .path-text { font-family: 'JetBrains Mono', monospace; font-weight: 500; color: var(--text); }
        .timestamp { color: var(--subtext); font-size: 0.85rem; }

        .section-header {
            font-size: 0.8rem;
            font-weight: 600;
            text-transform: uppercase;
            color: var(--subtext);
            letter-spacing: 0.05em;
            margin-bottom: 0.75rem;
            margin-top: 1.5rem;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }
        .section-header::after { content: ""; flex: 1; height: 1px; background: #334155; }

        .kv-grid {
            display: grid;
            grid-template-columns: auto 1fr;
            gap: 0.25rem 1rem;
            background: var(--code-bg);
            padding: 1rem;
            border-radius: 12px;
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.85rem;
            max-height: 200px;
            overflow-y: auto;
        }
        .key { color: var(--header-key); font-weight: 500; }
        .val { color: var(--header-val); word-break: break-all; }

        .body-pre {
            background: var(--code-bg);
            padding: 1rem;
            border-radius: 12px;
            font-family: 'JetBrains Mono', monospace;
            overflow-x: auto; /* Fix bug 2: Local horizontal scroll */
            overflow-y: auto;
            max-height: 200px; /* Constrained to match headers */
            font-size: 0.85rem;
            margin: 0;
            color: #cbd5e1;
            border-left: 3px solid var(--accent);
            width: 100%;
            box-sizing: border-box;
            white-space: pre-wrap;
            word-break: break-all;
        }
        .badge {
            font-size: 0.7rem;
            background: #334155;
            color: var(--subtext);
            padding: 0.2rem 0.6rem;
            border-radius: 20px;
            font-weight: 600;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>📡 Webhook Receiver</h1>
            <div class="controls">
                <button onclick="fetchEvents()">Refresh Now</button>
                <button onclick="clearEvents()">Clear history</button>
            </div>
        </header>

        <div id="status" style="margin-bottom: 2rem; font-size: 0.95rem; color: var(--subtext);">
            Watching for traffic at <code style="color: var(--accent); background: #1e293b; padding: 0.2rem 0.4rem; border-radius: 4px;">/webhook</code>
        </div>

        <div id="list" class="event-list"></div>
    </div>

    <script>
        const scrollCache = {}; // Fix bug 1: Store scroll positions

        async function fetchEvents() {
            try {
                const res = await fetch('/api/events');
                const data = await res.json();
                
                // Save current scrolls before re-rendering
                document.querySelectorAll('.event-card').forEach(card => {
                    const id = card.getAttribute('data-id');
                    const headersEl = card.querySelector('.headers-section');
                    const bodyEl = card.querySelector('.body-pre');
                    if (id) {
                        scrollCache[id] = {
                            headersTop: headersEl ? headersEl.scrollTop : 0,
                            bodyTop: bodyEl ? bodyEl.scrollTop : 0,
                            bodyLeft: bodyEl ? bodyEl.scrollLeft : 0
                        };
                    }
                });

                renderEvents(data);

                // Restore scrolls after rendering
                document.querySelectorAll('.event-card').forEach(card => {
                    const id = card.getAttribute('data-id');
                    if (id && scrollCache[id]) {
                        const state = scrollCache[id];
                        const headersEl = card.querySelector('.headers-section');
                        const bodyEl = card.querySelector('.body-pre');
                        if (headersEl) headersEl.scrollTop = state.headersTop;
                        if (bodyEl) {
                            bodyEl.scrollTop = state.bodyTop;
                            bodyEl.scrollLeft = state.bodyLeft;
                        }
                    }
                });

            } catch (e) {
                console.error("Failed to fetch events", e);
            }
        }

        async function clearEvents() {
            if(!confirm('Clear history?')) return;
            await fetch('/api/clear', { method: 'POST' });
            fetchEvents();
        }

        function renderKV(obj, className = "") {
            const keys = Object.keys(obj);
            if (keys.length === 0) return '<div style="color: var(--subtext); font-style: italic;">None</div>';
            return `<div class="kv-grid \${className}">` + 
                keys.map(k => `<span class="key">\${k}:</span><span class="val">\${obj[k]}</span>`).join('') + 
                `</div>`;
        }

        function formatBody(body) {
            if (!body) return '(empty body)';
            try {
                // Try beautifying if it's JSON
                const parsed = JSON.parse(body);
                return JSON.stringify(parsed, null, 2);
            } catch (e) {
                return body; // Fallback to raw text
            }
        }

        function renderEvents(events) {
            const list = document.getElementById('list');
            if (!events || events.length === 0) {
                list.innerHTML = '<div class="empty-state">No webhooks received yet.<br><small>URL: https://webhook-test-ftog.onrender.com/webhook</small></div>';
                return;
            }

            list.innerHTML = events.map(e => `
                <div class="event-card" data-id="\${e.timestamp}">
                    <div class="event-meta">
                        <div class="path-group">
                            <span class="method">\${e.method}</span>
                            <span class="path-text">\${e.path}</span>
                        </div>
                        <div class="timestamp">\${new Date(e.timestamp).toLocaleString([], { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', second: '2-digit' })}</div>
                    </div>

                    <div style="margin-bottom: 1rem;">
                        <span class="badge">FROM \${e.sourceIp}</span>
                    </div>

                    <div class="section-header">Query Parameters</div>
                    \${renderKV(e.queryParams)}

                    <div class="section-header">Headers</div>
                    \${renderKV(e.headers, "headers-section")}

                    <div class="section-header">Body Content</div>
                    <pre class="body-pre">\${formatBody(e.body)}</pre>
                </div>
            `).join('');
        }

        // Auto refresh
        setInterval(fetchEvents, 3000);
        fetchEvents();
    </script>
</body>
</html>
''';
}
