import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

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

  print('Received webhook: ${req.method} ${req.url}');

  return Response.ok(
    jsonEncode({'status': 'ok', 'received': true}),
    headers: {'Content-Type': 'application/json'},
  );
}

Response _clearHandler(Request req) {
  _events.clear();
  return Response.ok(
    jsonEncode({'status': 'cleared'}),
    headers: {'Content-Type': 'application/json'},
  );
}

// --- Main ---

void main(List<String> args) async {
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
        body {
            font-family: 'Outfit', sans-serif;
            background: var(--bg);
            color: var(--text);
            margin: 0;
            padding: 2rem;
            display: flex;
            flex-direction: column;
            align-items: center;
        }
        .container {
            width: 100%;
            max-width: 1000px;
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
        .event-list { display: grid; gap: 1.5rem; }
        .event-card {
            background: var(--card);
            border-radius: 20px;
            padding: 1.5rem;
            border: 1px solid #334155;
            box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
            transition: border-color 0.2s;
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
            overflow-x: auto;
            max-height: 400px;
            font-size: 0.9rem;
            margin: 0;
            color: #cbd5e1;
            border-left: 3px solid var(--accent);
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
        async function fetchEvents() {
            try {
                const res = await fetch('/api/events');
                const data = await res.json();
                renderEvents(data);
            } catch (e) {
                console.error("Failed to fetch events", e);
            }
        }

        async function clearEvents() {
            if(!confirm('Clear history?')) return;
            await fetch('/api/clear', { method: 'POST' });
            fetchEvents();
        }

        function renderKV(obj) {
            const keys = Object.keys(obj);
            if (keys.length === 0) return '<div style="color: var(--subtext); font-style: italic;">None</div>';
            return `<div class="kv-grid">` + 
                keys.map(k => `<span class="key">\${k}:</span><span class="val">\${obj[k]}</span>`).join('') + 
                `</div>`;
        }

        function renderEvents(events) {
            const list = document.getElementById('list');
            if (!events || events.length === 0) {
                list.innerHTML = '<div class="empty-state">No webhooks received yet.<br><small>Try: curl http://localhost:8080/webhook?hello=world</small></div>';
                return;
            }

            list.innerHTML = events.map(e => `
                <div class="event-card">
                    <div class="event-meta">
                        <div class="path-group">
                            <span class="method">\${e.method}</span>
                            <span class="path-text">\${e.path}</span>
                        </div>
                        <div class="timestamp">\${new Date(e.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}</div>
                    </div>

                    <div style="margin-bottom: 1rem;">
                        <span class="badge">FROM \${e.sourceIp}</span>
                    </div>

                    <div class="section-header">Query Parameters</div>
                    \${renderKV(e.queryParams)}

                    <div class="section-header">Headers</div>
                    \${renderKV(e.headers)}

                    <div class="section-header">Body Content</div>
                    <pre class="body-pre">\${e.body || '(empty body)'}</pre>
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
