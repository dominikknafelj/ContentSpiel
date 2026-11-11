// The browser's half of a passkey ceremony, making one (`create`) or using
// one (`get`), with no library: the server's options in,
// the credential out as JSON for the `credential` parameter.
//
// THE PROMPT OPENS IN THE PRESS. WebKit lets `navigator.credentials.create`
// and `.get` run only inside a user gesture, and an `await` before the call
// ends the gesture. So a caller fetches the options before the press
// (`fetchOptions`) and holds them, and `create` and `get` call the browser
// at once, synchronously from the press, returning its promise.
//
// The options arrive as the server's JSON (binary members base64url).
// Where the browser parses that itself (`PublicKeyCredential.
// parseCreationOptionsFromJSON` / `parseRequestOptionsFromJSON`) it does;
// elsewhere the members the API takes as bytes are decoded here: the
// challenge, the user's id and each listed credential's id. The answer is
// written back the same way (`credential.toJSON()`, or base64url by hand).
//
// Nothing here keeps a challenge, a credential or a key: each lives in the
// caller's hands for one press.

export function supported() {
  return typeof window.PublicKeyCredential === "function" && typeof navigator.credentials?.get === "function"
}

// POSTs `body` as JSON with the page's CSRF token and answers
// `{ status, options }`, `options` null unless the answer was JSON.
export async function fetchOptions(url, body = {}) {
  const response = await fetch(url, {
    method: "POST",
    credentials: "same-origin",
    headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
    body: JSON.stringify(body),
  })
  const json = response.headers.get("Content-Type")?.includes("application/json")
  return { status: response.status, options: json ? await response.json() : null }
}

export function create(options) {
  const publicKey = PublicKeyCredential.parseCreationOptionsFromJSON
    ? PublicKeyCredential.parseCreationOptionsFromJSON(options)
    : {
        ...options,
        challenge: decode(options.challenge),
        user: { ...options.user, id: decode(options.user.id) },
        excludeCredentials: (options.excludeCredentials || []).map((credential) => ({ ...credential, id: decode(credential.id) })),
      }
  return navigator.credentials.create({ publicKey })
}

export function get(options) {
  const publicKey = PublicKeyCredential.parseRequestOptionsFromJSON
    ? PublicKeyCredential.parseRequestOptionsFromJSON(options)
    : {
        ...options,
        challenge: decode(options.challenge),
        allowCredentials: (options.allowCredentials || []).map((credential) => ({ ...credential, id: decode(credential.id) })),
      }
  return navigator.credentials.get({ publicKey })
}

export function toJSON(credential) {
  if (typeof credential.toJSON === "function") return JSON.stringify(credential.toJSON())

  const response = credential.response
  const out = {}
  for (const name of ["clientDataJSON", "attestationObject", "authenticatorData", "signature", "userHandle"]) {
    if (response[name]) out[name] = encode(response[name])
  }
  if (typeof response.getTransports === "function") out.transports = response.getTransports()
  return JSON.stringify({
    id: credential.id,
    rawId: encode(credential.rawId),
    type: credential.type,
    authenticatorAttachment: credential.authenticatorAttachment ?? undefined,
    clientExtensionResults: credential.getClientExtensionResults(),
    response: out,
  })
}

// The person closed the prompt, or it timed out, or another one took its
// place: nothing to tell them.
export function cancelled(error) {
  return error?.name === "NotAllowedError" || error?.name === "AbortError"
}

function csrfToken() {
  return document.querySelector("meta[name=csrf-token]")?.content ?? ""
}

function decode(text) {
  const base64 = text.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(text.length / 4) * 4, "=")
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0)).buffer
}

function encode(buffer) {
  const bytes = new Uint8Array(buffer)
  let binary = ""
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}
