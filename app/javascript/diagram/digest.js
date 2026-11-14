// The `from` of a Diagram block's drawing: the SHA-256, in lower-case hex, of
// the UTF-8 of the source AS THE SERVER STORES IT, which is what
// `Diagrams::Drawing.digest` hashes and `Drawing#current?` compares.
//
// The server casts a `:mermaid` value before it stores it (`TYPED_TEXT` in
// `app/models/content_model/field_types.rb`): CR and CRLF become LF, and the
// blank lines before the first line and after the last are dropped, a line
// being blank when Ruby's `strip` leaves nothing of it (ASCII white space and
// NUL, never a no-break space). `cast` is that port, and a change of the
// Ruby's rule is a change here, or every drawing is stored as not current.
const RUBY_SPACE = /^[\0\t\n\v\f\r ]*$/

export function cast(text) {
  const lines = String(text).replace(/\r\n?/g, "\n").split("\n")
  while (lines.length && RUBY_SPACE.test(lines[0])) lines.shift()
  while (lines.length && RUBY_SPACE.test(lines[lines.length - 1])) lines.pop()
  return lines.join("\n")
}

export async function digest(source) {
  const bytes = new TextEncoder().encode(cast(source))
  const hash = await crypto.subtle.digest("SHA-256", bytes)
  return Array.from(new Uint8Array(hash), (byte) => byte.toString(16).padStart(2, "0")).join("")
}
