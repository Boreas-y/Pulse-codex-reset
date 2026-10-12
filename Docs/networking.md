# Networking

Owns the proxy boundary for traffic Pulse starts. Per-provider routes and authentication still belong in [providers/README.md](providers/README.md); updates belong in [releasing.md](releasing.md).

## Setting

Settings → Network and refresh offers three modes (`NetworkProxyMode`):

- **No Proxy** (`direct`) connects directly, whatever macOS or a shell says. `URLSession` gets an empty `connectionProxyDictionary` — empty means no proxy, where nil means the system's — and helper processes get Pulse's environment with every proxy variable removed. A saved custom endpoint is kept for when the custom proxy is chosen again.
- **System Proxy** (`system`) is the default and preserves the behaviour from before this setting existed. `URLSession` uses macOS's proxy configuration, and helper processes inherit Pulse's environment unchanged.
- **Custom Proxy** (`manual`) accepts an HTTP CONNECT or SOCKS5 proxy without authentication. Host and port are one commit: Return or leaving either field attempts to save both, and an empty host or a port outside 1–65535 does not replace any saved endpoint. There is deliberately no per-provider override.

The stored tokens are `direct`, `system` and `manual`; an older build that reads `direct` cannot decode it and falls back to the system's proxy.

`AppSettings.networkProxy` is one Codable value in `UserDefaults`. A mode or type selection is saved immediately; text remains local to `NetworkPane` until the complete endpoint passes validation. Every saved change goes through `AppSettings.onChange`, so all enabled accounts are asked again rather than waiting for the next timer tick.

## URLSession boundary

`NetworkSession` owns the default session and applies the setting to every external session Pulse creates. No Proxy sets `connectionProxyDictionary` to `[:]`. Custom HTTP uses `ProxyConfiguration(httpCONNECTProxy:)`; SOCKS5 uses `ProxyConfiguration(socksv5Proxy:)`. Replacing the setting cancels the previous shared session so requests queued by the settings change cannot continue to reuse its connections.

The boundary includes:

- provider usage requests, including the isolated ephemeral sessions used for borrowed browser cookies;
- OAuth, device-code and browser-login token exchanges;
- the models.dev price download;
- the status-page reads on the Codex, Claude Code and DeepSeek panes, and the outage notification's ([providers/codex.md](providers/codex.md#service-status), [providers/claude-code.md](providers/claude-code.md#service-status), [providers/deepseek.md](providers/deepseek.md#service-status)).

Cookie storage, cache and redirect policies still belong to each caller. Applying a proxy must not turn a borrowed browser session into a process-wide cookie jar or allow its hand-written `Cookie` header across a redirect.

Antigravity is the exception: its session reaches the editor's language server at `https://127.0.0.1:<port>` and stays outside `NetworkSession`. Loopback traffic is never sent to the custom proxy.

## Helper processes

A custom HTTP proxy starts `codex app-server` and `arkcli` with `HTTP_PROXY` and `HTTPS_PROXY`; SOCKS5 uses `ALL_PROXY`. Both also receive `NO_PROXY=localhost,127.0.0.1,::1`. Conflicting inherited upper- and lower-case proxy variables are removed first. Whether a helper supports SOCKS5 is the helper's decision.

Selecting System Proxy sets no child environment. This is intentional: a helper launched from Finder or a login item inherits no shell proxy, while one launched from a terminal may. System Proxy means preserving that existing behaviour, not manufacturing environment variables from macOS network settings. No Proxy is the opposite: it removes the upper- and lower-case `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY` and `NO_PROXY` a helper would otherwise inherit, so a proxy exported in the shell that launched Pulse does not reach it either.

Every helper CLI Pulse starts — `codex app-server`, Kiro's ACP client, `arkcli`, Alibaba's `bl` — gets the folder it was found in at the front of `PATH` (`BoundedProcess.environment(leading:over:)`), because an npm-installed CLI is a Node script and a GUI app's `PATH` has no `node` ([providers/codex.md](providers/codex.md#app-server--sigpipe--path)).

Extensions do **not** inherit Pulse's environment under either setting: they get a short list of basics plus whatever proxy variables are in effect, so a custom proxy reaches them, No Proxy leaves them none, and a token exported for another tool does not. [extensions.md](extensions.md)

`UsageStore.settingsChanged` shuts down an existing Codex app server before it queues the new full pass. The next request starts a child with the new environment. `arkcli` is already one process per request.

## Updates

Sparkle owns its network session and exposes no public session-configuration or proxy hook. Update checks therefore always follow macOS system proxy settings, regardless of Pulse's Network setting — No Proxy included. Do not imply otherwise in the READMEs or settings copy.
