// The first Mermaid diagram of a Markdown text: the body of its first fenced
// code block whose opening line names `mermaid` (```` ```mermaid ```` or
// `~~~mermaid`), and whether another such block follows it.
//
// A fence opens on a line of at least three backticks or tildes at the
// line's start (a backtick fence's info string holds no backtick, as in
// CommonMark) and closes on a line of the same character, at least as many,
// with nothing after it but spaces; a closing line may stand up to three
// spaces in, as CommonMark allows. A fence that never closes runs to the end
// of the text. A fence inside another fence is text (a ````markdown example
// that shows a mermaid fence is not the diagram). Line endings are the
// caller's to make `\n`.
const OPENING = /^(`{3,}|~{3,})(.*)$/
const MERMAID = /^(`{3,}|~{3,})\s*mermaid\b/i

// `{ text, more }`, or null when the text holds no mermaid fence.
export function firstMermaidFence(text) {
  const lines = text.split("\n")
  let found = null
  let index = 0
  while (index < lines.length) {
    const fence = opening(lines[index])
    index += 1
    if (!fence) continue
    const start = index
    while (index < lines.length && !closes(lines[index], fence)) index += 1
    const body = lines.slice(start, index).join("\n")
    index += 1
    if (!MERMAID.test(fence.line)) continue
    if (found !== null) return { text: found, more: true }
    found = body
  }
  return found === null ? null : { text: found, more: false }
}

function opening(line) {
  const match = OPENING.exec(line)
  if (!match) return null
  const [ , marks, info ] = match
  if (marks[0] === "`" && info.includes("`")) return null
  return { line, character: marks[0], length: marks.length }
}

function closes(line, fence) {
  const match = /^ {0,3}(`{3,}|~{3,})\s*$/.exec(line)
  return Boolean(match) && match[1][0] === fence.character && match[1].length >= fence.length
}
