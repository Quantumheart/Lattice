# Invite landing page

This doc shows homeserver admins how to host a short URL like
`https://example.com/invite?server=example.com&token=abc123` that opens
Kohera at the registration screen with the token pre-filled. It pairs
with the `kohera://` URI scheme wired in the client.

Pick **Option A** (nginx redirect) for most deployments. Fall back to
**Option B** (HTML page) if your proxy strips non-HTTP redirects or you
don't control the server-side redirect layer.

## Option A — nginx 302 redirect (preferred)

Simplest, no HTML, no JS. The token never enters any page DOM; the
browser sees only a redirect header.

```nginx
# Serve at /invite on the homeserver vhost.
location = /invite {
    # Fall back to the current host if ?server= is omitted.
    set $kohera_server $arg_server;
    if ($kohera_server = "") {
        set $kohera_server $host;
    }

    # Suppress intermediate caching of the invite URL.
    add_header Cache-Control "no-store" always;

    return 302 "kohera://register?server=$kohera_server&token=$arg_token";
}
```

Test:

```bash
curl -sI 'https://example.com/invite?token=abc123' | grep -i location
# Location: kohera://register?server=example.com&token=abc123
```

## Option B — static HTML landing

Use this when Option A isn't available (restrictive proxies, managed
hosting without redirect control). Any static-file host works.

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="robots" content="noindex,nofollow">
  <title>Opening Kohera…</title>
</head>
<body>
  <noscript>
    <p>JavaScript is required to continue. If Kohera does not open,
      <a href="https://github.com/Quantumheart/kohera/releases">download it here</a>.</p>
  </noscript>
  <p id="fallback" style="display:none">
    If Kohera does not open automatically,
    <a href="https://github.com/Quantumheart/kohera/releases">download it here</a>.
  </p>
  <script>
    (function () {
      var params = new URLSearchParams(window.location.search);
      var token = params.get('token');
      var server = params.get('server') || window.location.hostname;
      if (token) {
        window.location.replace(
          'kohera://register?server=' + encodeURIComponent(server) +
          '&token=' + encodeURIComponent(token)
        );
        // If the scheme isn't registered, the page stays on screen;
        // reveal the download link after a short delay.
        setTimeout(function () {
          document.getElementById('fallback').style.display = 'block';
        }, 1500);
      } else {
        document.getElementById('fallback').style.display = 'block';
      }
    })();
  </script>
</body>
</html>
```

Serve with a cache-discouraging header:

```nginx
location = /invite.html {
    add_header Cache-Control "no-store" always;
    try_files $uri =404;
}
location = /invite {
    try_files /invite.html =404;
}
```

Notes on the HTML:

- `URLSearchParams.get` returns decoded values; `encodeURIComponent`
  re-encodes them for the scheme URL.
- The token is never written into the DOM — only passed through
  `window.location.replace`.
- `window.location.replace` doesn't push a new history entry.
- `<meta name="robots">` keeps the page out of search indexes.

## Web app direct link

If you know the user is on `kohera-web`, skip the scheme entirely and
link straight into the web app. GoRouter accepts `server` and `token`
on the register route:

```
https://kohera.example/#/register?server=example.com&token=abc123
```

This avoids OS-level scheme prompts but only works for the web build.

## Operational notes

- **Use single-use tokens with a short TTL.** Synapse's
  `/_synapse/admin/v1/registration_tokens` endpoint supports
  `uses_allowed` and `expiry_time` — set both.
- **The invite URL is in browser history.** Anyone who clicks the link
  (or anything with access to their history) sees the token. Mitigate
  with short TTLs; assume the URL is disclosed the moment it reaches a
  browser.
- **Don't log the URL.** Standard access logs capture query strings.
  Configure nginx to drop query strings for `/invite`:

  ```nginx
  location = /invite {
      access_log off;
      # ... (rest of Option A config)
  }
  ```

- **Scheme registration varies per OS.** The Kohera client registers
  `kohera://` on install (Android manifest, iOS/macOS `CFBundleURLTypes`,
  Linux `.desktop`). On Linux, users may need
  `xdg-mime default io.github.quantumheart.kohera.desktop x-scheme-handler/kohera`
  after install.
