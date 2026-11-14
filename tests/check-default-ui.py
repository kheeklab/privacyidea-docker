#!/usr/bin/env python3
"""Exercise the default UI entry path from inside a running container.

Verifies that:
- GET / redirects to /app/v2/en/ and returns 200 privacyIDEA HTML (English)
- GET / with Accept-Language: de redirects to /app/v2/de/ (locale routing)
- GET / with pi_ui_locale=de cookie redirects to /app/v2/de/
- Redirect Location is a path-only value (no open-redirect via spoofed Host)
- GET /app/v2/en/ and /app/v2/de/ both return 200 privacyIDEA HTML
- Readiness endpoint reports ready
- Admin authentication succeeds

Requires PI_ADMIN_USER and PI_ADMIN_PASSWORD environment variables.
Runs inside the container against 127.0.0.1:8080 (Gunicorn must be ready).
"""
import http.client
import json
import os
import urllib.parse
import urllib.request

BASE = 'http://127.0.0.1:8080'


def get(path, headers=None, follow_redirects=True):
    request = urllib.request.Request(BASE + path, headers=headers or {})
    with urllib.request.urlopen(request, timeout=15) as response:
        return response.status, response.url, response.read()


def get_no_follow(path, headers=None):
    conn = http.client.HTTPConnection('127.0.0.1', 8080, timeout=15)
    conn.request('GET', path, headers=headers or {})
    resp = conn.getresponse()
    location = resp.getheader('Location', '')
    resp.read()
    conn.close()
    return resp.status, location


# / → /app/v2/en/ (default, no Accept-Language)
status, url, body = get('/')
parsed = urllib.parse.urlparse(url)
assert status == 200 and parsed.path == '/app/v2/en/' and b'privacyIDEA' in body, \
    f'Default route: expected /app/v2/en/ 200, got {parsed.path} {status}'
print('PASS: / → /app/v2/en/')

# / with Accept-Language: en → /app/v2/en/
status, url, body = get('/', {'Accept-Language': 'en'})
parsed = urllib.parse.urlparse(url)
assert status == 200 and parsed.path == '/app/v2/en/' and b'privacyIDEA' in body, \
    f'EN route: expected /app/v2/en/ 200, got {parsed.path} {status}'
print('PASS: / Accept-Language:en → /app/v2/en/')

# / with Accept-Language: de → /app/v2/de/
status, url, body = get('/', {'Accept-Language': 'de'})
parsed = urllib.parse.urlparse(url)
assert status == 200 and parsed.path == '/app/v2/de/' and b'privacyIDEA' in body, \
    f'DE route: expected /app/v2/de/ 200, got {parsed.path} {status}'
print('PASS: / Accept-Language:de → /app/v2/de/')

# / with cookie pi_ui_locale=de → /app/v2/de/
status, url, body = get('/', {'Accept-Language': 'en', 'Cookie': 'pi_ui_locale=de'})
parsed = urllib.parse.urlparse(url)
assert status == 200 and parsed.path == '/app/v2/de/' and b'privacyIDEA' in body, \
    f'Cookie route: expected /app/v2/de/ 200, got {parsed.path} {status}'
print('PASS: / cookie pi_ui_locale=de → /app/v2/de/')

# No open redirect: Location must be path-only (no host)
status, location = get_no_follow('/', {'Host': 'attacker.invalid', 'X-Forwarded-Host': 'attacker.invalid'})
assert status == 302 and location in ('/app/v2/en/', '/app/v2/de/') and 'attacker' not in location, \
    f'Open-redirect guard: got Location={location!r}'
print(f'PASS: open-redirect guard (Location={location!r})')

# /app/v2/en/ and /app/v2/de/ serve HTML directly
for locale in ('en', 'de'):
    status, url, body = get(f'/app/v2/{locale}/')
    assert status == 200 and b'privacyIDEA' in body, \
        f'/app/v2/{locale}/ expected 200 privacyIDEA HTML, got {status}'
print('PASS: /app/v2/en/ and /app/v2/de/ serve HTML')

# Readiness
status, _, body = get('/healthz/readyz')
result = json.loads(body)['result']['value']['status']
assert result == 'ready', f'Readiness: expected ready, got {result!r}'
print('PASS: /healthz/readyz ready')

# Admin authentication
payload = urllib.parse.urlencode({
    'username': os.environ['PI_ADMIN_USER'],
    'password': os.environ['PI_ADMIN_PASSWORD'],
}).encode()
with urllib.request.urlopen(BASE + '/auth', data=payload, timeout=15) as response:
    role = json.load(response)['result']['value']['role']
assert role == 'admin', f'Auth: expected admin role, got {role!r}'
print('PASS: /auth admin authentication')

# Script-root prefix test (unit-level, no running server needed)
from privacyidea.app import create_app  # noqa: E402
app = create_app(config_name='production', config_file='/etc/privacyidea/pi.cfg')
with app.test_client() as client:
    response = client.get('/', headers={'Accept-Language': 'en'},
                          environ_overrides={'SCRIPT_NAME': '/prefix'})
    assert response.status_code == 302 and response.headers['Location'] == '/prefix/app/v2/en/', \
        f'Prefix: expected /prefix/app/v2/en/, got {response.headers.get("Location")!r}'
    print('PASS: script-root prefix preserved in redirect')
    app.config['PI_UI_DEACTIVATED'] = True
    response = client.get('/')
    assert response.status_code == 200 and 'Location' not in response.headers, \
        'PI_UI_DEACTIVATED should serve HTML, not redirect'
    print('PASS: PI_UI_DEACTIVATED returns 200 HTML (no redirect)')

print('PASS: default UI, locale, prefix, deactivation, open-redirect, readiness and admin authentication')
