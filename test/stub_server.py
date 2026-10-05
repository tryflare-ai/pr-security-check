"""Minimal stand-in for the Flare API used by the smoke tests.

Records every request body to argv[2] (one JSON object per line) and replies
with canned responses. Model-like text deliberately contains printf format
specifiers, backslashes, a leading "@" and shell metacharacters.
"""
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

HOSTILE = "100% sure: %s %n \\\\ \\n $(touch /tmp/flare-pwned) `id` @/etc/passwd"

RESPONSES = {
    "pr-check": (200, {
        "findings": [
            {"severity": "critical", "file": "iam/admin-policy.json", "line": 3,
             "title": "Wildcard admin", "explanation": HOSTILE, "suggestion": "Scope it %d"},
            {"severity": "medium", "file": "main.tf", "line": 1,
             "title": "Public bucket", "explanation": "acl = public-read", "suggestion": "private"},
        ],
        "summary": "1 critical, 1 medium",
        "files_analyzed": 2,
        "files_truncated": 0,
    }),
    "deploy": (202, {"queued": True, "analysis_at": "2026-10-05T12:00:00Z", "connector_name": "prod %s"}),
    "incident-scope": (200, {
        "total_logs_analyzed": 42, "truncated": False, "events_dropped": 0,
        "narrative": HOSTILE,
        "time_window": {"from": "2026-10-05T00:00:00Z", "to": "2026-10-05T01:00:00Z"},
        "timeline": [{"timestamp": "t1", "service": "iam", "actor": "a@b", "action": "SetIamPolicy", "severity": "critical"}],
    }),
    "changelog": (200, {
        "markdown": "## Week\n" + HOSTILE,
        "json": {"risk_score": 7.5, "period": {"start": "2026-09-28T00:00:00Z", "end": "2026-10-05T00:00:00Z"}},
        "metadata": {"total_logs": 1000, "sampled": False},
    }),
}

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(204)
        self.end_headers()

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)) or 0)
        auth = self.headers.get("Authorization", "")
        with open(sys.argv[2], "a") as f:
            f.write(json.dumps({"path": self.path, "auth": auth, "body": json.loads(body or b"{}")}) + "\n")
        route = self.path.rstrip("/").rsplit("/", 1)[-1]
        if auth == "Bearer bad-token-0000":
            status, payload = 401, {"error": "Invalid token"}
        elif auth == "Bearer limit-token-000":
            status, payload = 429, {"error": "Daily analysis limit reached"}
        else:
            status, payload = RESPONSES.get(route, (404, {"error": "not found"}))
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass

HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
