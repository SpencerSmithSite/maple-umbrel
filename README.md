![Maple AI running on Umbrel](screenshot.png)

# Maple AI — Umbrel Community App

This repo packages [Maple AI](https://github.com/OpenSecretCloud/Maple) as a community app for [Umbrel](https://umbrel.com).

> **I am not the developer of Maple.** Maple is built by [OpenSecret](https://opensecret.cloud). I just packaged it for Umbrel.

## What is Maple?

Maple is a private AI chat app that runs your conversations through Trusted Execution Environments (TEEs) — secure enclaves that guarantee no one, not even OpenSecret, can read your messages. It also exposes an OpenAI-compatible API endpoint so you can connect tools like Cursor, Open WebUI, or LiteLLM to it using your Maple API key.

## Browser Requirements

Maple uses your browser's cryptographic APIs to verify that it is communicating with a genuine Trusted Execution Environment (TEE) before sending any data. These APIs (`crypto.subtle`) are restricted by browsers to **secure contexts only** — meaning HTTPS or localhost.

Umbrel serves apps over plain HTTP on the local network, so some browsers need a one-time setting change to grant this origin secure context access.

### When you DO need to change a browser setting

If you are accessing Maple at `http://umbrel.local:3001` over your local network, follow the steps for your browser:

**Chrome or Edge (recommended)**
1. Go to `chrome://flags/#unsafely-treat-insecure-origin-as-secure`
2. Add `http://umbrel.local:3001` to the text box
3. Click **Enable**, then **Relaunch**

**Firefox**
1. Go to `about:config` and accept the warning
2. Search for `dom.securecontext.allowlist`
3. If the preference does not exist, create it as a **String**
4. Set the value to `http://umbrel.local:3001`
5. Restart Firefox

**Safari / iOS Safari**
Safari does not provide a built-in bypass for this restriction.
Use Chrome or Firefox on the same network, or use one of the no-change-required options below.

### When you do NOT need to change any browser setting

In these situations the app is already served over a secure context and works in all browsers without any configuration:

- **Cloudflare Tunnel** — if you have a Cloudflare Tunnel configured on your Umbrel, access Maple through your tunnel's HTTPS URL instead of `http://umbrel.local:3001`. All browsers work automatically.

- **Tor Browser** — Umbrel provides a Tor hidden service (.onion address) for each app. Tor Browser treats `.onion` addresses as secure contexts. Find your Maple .onion address in the Umbrel dashboard under Remote Access. Tor Browser works without any setting changes.

### Why this is necessary

When you log in or send a message, Maple asks the server to prove it is running inside a genuine AWS Nitro Enclave (TEE attestation). Verifying that proof requires `crypto.subtle` — the browser's built-in cryptographic API. Browsers intentionally restrict this API to HTTPS to prevent interception attacks. The browser setting above tells your browser to treat your local Umbrel as trusted, enabling the same security guarantees you would have over HTTPS.

## Installation

1. Open the Umbrel App Store
2. Click the **⋯** (horizontal ellipsis) menu in the top-right corner
3. Select **Add community app store**
4. Paste this URL:
   ```
   https://github.com/SpencerSmithSite/maple-umbrel
   ```
5. Click **Add** — Maple AI will appear in your app store under the **AI** category

## Links

- Maple source code: https://github.com/OpenSecretCloud/Maple
- OpenSecret: https://opensecret.cloud
- Issues with this packaging: https://github.com/SpencerSmithSite/maple-umbrel/issues
