# ChatGPT OAuth

VibeCompose Public Alpha uses the user's ChatGPT account as its only provider
path. This is an unofficial integration with undocumented ChatGPT web
behavior, not an OpenAI public API contract.

## User flow

1. The user chooses **Use Browser Login** in Onboarding or Settings.
2. VibeCompose creates a one-time random `state` value and PKCE verifier.
3. The default browser opens the OpenAI authorization page.
4. A loopback-only callback listener waits at
   `http://localhost:1455/auth/callback`.
5. VibeCompose validates the callback method, path, duplicate parameters, and
   exact `state`.
6. The authorization code is exchanged with the PKCE verifier.
7. The resulting session is stored in macOS Keychain.

The app requests `openid profile email offline_access`. It never asks for or
stores the user's ChatGPT password.

## Local storage

- Keychain service: `app.vibecompose.mac.ChatGPTSession`
- Configuration and logs do not intentionally contain access tokens, refresh
  tokens, ID tokens, cookies, or authorization headers.
- Sign out deletes the saved Keychain session.
- **Delete All Data** also deletes the saved session.

## Security properties

- Authorization Code flow with PKCE `S256`
- cryptographically random verifier and callback state
- exact callback path and one-time state validation
- duplicate security-sensitive callback parameters rejected
- ten-minute browser-login timeout
- refresh operations coalesced so concurrent callers do not race session state
- late refresh results rejected after sign-out or session replacement

## Upstream dependency

After login, VibeCompose sends requests directly to approved
`https://chatgpt.com` paths. These paths are undocumented and may change.
Managed requests reject non-HTTPS schemes, alternate hosts, embedded
credentials, unexpected ports, fragments, redirects, and unsupported query
parameters.

When the integration stops working, capture only the smallest non-sensitive
error and follow
[the upstream incident playbook](../support/upstream-incident-playbook.md).
Never post tokens, cookies, audio, transcripts, or private documents.
