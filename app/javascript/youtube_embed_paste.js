// Converts a pasted YouTube URL into an embedded <action-text-attachment>
// (design spec section 8), wherever a Trix editor exists on an Avo page.
// A plain document-level listener rather than a per-field Stimulus
// controller: "trix-paste" bubbles to `document` from any <trix-editor> on
// the page, the same way @rails/actiontext listens for "trix-attachment-add"
// globally to drive file uploads (see actiontext.esm.js).
const YOUTUBE_URL_PATTERN =
  /^(?:https?:\/\/)?(?:www\.)?(?:youtube(?:-nocookie)?\.com\/(?:watch\?(?:.*&)?v=|embed\/|shorts\/)|youtu\.be\/)([\w-]{11})(?:[?&].*)?$/

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content
}

// Matches the server partial (app/views/youtube_embeds/_youtube_embed.html.erb)
// closely enough to be indistinguishable to a viewer -- this is only ever
// shown until the async round trip below replaces it with the real,
// sgid-resolved attachment, never persisted as-is unless that round trip
// fails (see the `contentType` note below).
function embedHtmlFor(videoId) {
  return `<div class="content-block content-block--youtube-embed"><div class="youtube-embed__frame"><iframe src="https://www.youtube-nocookie.com/embed/${videoId}" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe></div></div>`
}

async function findOrCreateEmbed(url) {
  const response = await fetch("/avo/youtube_embeds", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      "X-CSRF-Token": csrfToken()
    },
    body: JSON.stringify({ url })
  })

  return response.ok ? response.json() : null
}

document.addEventListener("trix-paste", async (event) => {
  const { paste, target } = event
  const url = paste.string?.trim()
  if (!url) return

  const match = url.match(YOUTUBE_URL_PATTERN)
  if (!match) return

  const [, videoId] = match
  const editor = target.editor

  // `contentType` names something that contains "html" on purpose: if the
  // sgid round trip below never completes (offline, request failure), this
  // is exactly the shape ActionText::Attachables::ContentAttachment (a
  // built-in Rails fallback, not something this app wrote) resolves without
  // one -- the embed still renders next load, just as inline content rather
  // than a reusable YoutubeEmbed row.
  const attachment = new Trix.Attachment({
    content: embedHtmlFor(videoId),
    contentType: "text/html"
  })

  // Replaces the plain-text URL Trix already inserted, at the range it just
  // landed in -- otherwise the editor would hold both the typed URL and the
  // embed.
  editor.setSelectedRange(paste.range)
  editor.insertAttachment(attachment)

  const attributes = await findOrCreateEmbed(url)
  if (attributes) attachment.setAttributes(attributes)
})
