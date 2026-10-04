// The upload queue the Media screen (`admin--media-upload`) and the media
// picker (`admin--media-picker`) share (round 3, Task 9).
//
// Files go up ONE AT A TIME, each as a progress tile at the start of the grid:
// its name, a bar, "Uploading…". The server's answer (`Admin::MediaUploadResponses`)
// decides what happens next, never the browser's own idea of the file:
// - 201: the progress tile is replaced by the finished tile the server drew
//   (`json.tile`), nothing reloads -- a reload would throw away what an editor
//   is typing in the side panel and every other tile still in flight;
// - anything else: the tile STAYS, with the server's reason and a Dismiss
//   button. A refused file is reported, never lost, and never takes its
//   siblings or the page down with it.
//
// One at a time, not in parallel: the answer to the previous upload has been
// handled (its tile in the grid, the counts fixed) before the next file is
// sent, so what is on screen always follows what the server holds, and a batch
// of big files does not saturate the connection the editor's own autosaves
// share. XMLHttpRequest rather than `fetch` because only it reports how much
// of the body has gone up, which is what the bar is.
//
// A grid can be replaced under live tiles (a search in the picker, a tile click
// on the Media screen is a frame navigation): the tiles still uploading or
// failed are kept here and put back at the start of the new grid by `#reattach`.
export const TEXTS = {
  uploading: "Uploading…",
  dismiss: "Dismiss",
  failedNetwork: "Couldn't upload — check your connection",
  failedGeneric: "Upload failed"
}

export function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content || ""
}

// The segment counts the server sent back, written into the toolbar's spans
// (`Admin::MediaLibrary::ToolbarComponent.count_id`).
export function updateCounts(counts, { picker = false } = {}) {
  Object.entries(counts || {}).forEach(([ key, count ]) => {
    const span = document.getElementById(`media-${picker ? "picker-" : ""}count-${key}`)
    if (span) span.textContent = String(count)
  })
}

export class UploadTiles {
  // url:        the upload endpoint
  // grid:       () => the current grid <ul>, or null while there is none
  // fields:     () => extra form fields to send with each file (the search `q`)
  // onUploaded: ({ json, tile, file }) => void -- after the finished tile is in
  //             (when there is a grid to put it in)
  // announce:   (message) => void -- the polite live region
  constructor({ url, grid, fields = () => ({}), onUploaded = () => {}, announce = () => {} }) {
    Object.assign(this, { url, grid, fields, onUploaded, announce })
    this.queue = []
    this.live = []
    this.current = null
    this.running = false
    this.generation = 0
  }

  get busy() { return this.running || this.queue.length > 0 }

  add(files) {
    files.forEach((file) => {
      const entry = { file, li: this.buildTile(file.name) }
      this.live.push(entry)
      this.queue.push(entry)
    })
    this.reattach()
    this.run()
  }

  // Every tile still uploading or failed goes back to the start of whatever
  // grid is there now, in the order the files were added. Idempotent.
  reattach() {
    const list = this.grid()
    if (!list || this.live.length === 0) return

    list.parentElement?.querySelector(":scope > [data-media-empty]")?.remove()
    list.prepend(...this.live.map((entry) => entry.li))
  }

  // Stops what is running and forgets the rest: the picker closing, the screen
  // going away. An upload the server already received still lands (it is in the
  // library; "Unused" shows it) -- the browser just stops waiting for it.
  abort() {
    this.generation += 1
    this.queue = []
    this.current?.xhr?.abort()
    this.live.forEach((entry) => entry.li.remove())
    this.live = []
    this.current = null
    this.running = false
  }

  async run() {
    if (this.running) return

    this.running = true
    const generation = this.generation
    while (this.queue.length > 0 && generation === this.generation) {
      const entry = this.queue.shift()
      this.current = entry
      await this.upload(entry, generation)
    }
    if (generation === this.generation) {
      this.current = null
      this.running = false
    }
  }

  async upload(entry, generation) {
    const { status, json, aborted } = await this.send(entry)
    // Aborted, or the queue was reset while this was in flight.
    if (aborted || generation !== this.generation) return

    if (status === 201 && Number.isInteger(json?.id)) {
      this.finish(entry, json)
    } else {
      const errors = Array.isArray(json?.errors) && json.errors.length > 0 ? json.errors : null
      this.fail(entry, errors ? errors.join(". ") : (status === 0 ? TEXTS.failedNetwork : TEXTS.failedGeneric))
    }
  }

  send(entry) {
    return new Promise((resolve) => {
      const xhr = new XMLHttpRequest()
      entry.xhr = xhr
      xhr.open("POST", this.url)
      xhr.setRequestHeader("Accept", "application/json")
      xhr.setRequestHeader("X-CSRF-Token", csrfToken())
      xhr.upload.onprogress = (event) => {
        if (event.lengthComputable) this.progress(entry, event.loaded / event.total)
      }
      xhr.onload = () => {
        let json = null
        try { json = JSON.parse(xhr.responseText) } catch { /* an HTML answer (a sign-in redirect) is a failure */ }
        resolve({ status: xhr.status, json })
      }
      xhr.onerror = () => resolve({ status: 0, json: null })
      xhr.onabort = () => resolve({ aborted: true })

      const body = new FormData()
      body.append("file", entry.file)
      Object.entries(this.fields()).forEach(([ name, value ]) => body.append(name, value))
      xhr.send(body)
    })
  }

  finish(entry, json) {
    const template = document.createElement("template")
    template.innerHTML = json.tile || ""
    const tile = template.content.firstElementChild

    this.live = this.live.filter((candidate) => candidate !== entry)
    if (tile && entry.li.isConnected) {
      entry.li.replaceWith(tile)
    } else {
      entry.li.remove()
    }
    this.announce(`Uploaded ${entry.file.name}`)
    this.onUploaded({ json, tile, file: entry.file })
  }

  fail(entry, reason) {
    const { li } = entry
    li.dataset.state = "failed"
    li.querySelector("[data-upload-bar]").hidden = true
    li.querySelector("[data-upload-status]").textContent = reason
    li.querySelector("[data-upload-status]").className = "text-xs text-danger-ink"
    li.querySelector("[data-upload-dismiss]").hidden = false
    this.announce(`${entry.file.name} was not uploaded: ${reason}`)
  }

  progress(entry, fraction) {
    const fill = entry.li.querySelector("[data-upload-fill]")
    if (fill) fill.style.width = `${Math.round(fraction * 100)}%`
  }

  dismiss(entry) {
    this.live = this.live.filter((candidate) => candidate !== entry)
    entry.li.remove()
  }

  // One tile: a preview area with the bar along its bottom edge, then the name
  // and the status line. Not a link and not a button: nothing to choose yet.
  buildTile(name) {
    const li = document.createElement("li")
    li.dataset.uploadTile = ""
    li.setAttribute("role", "group")
    li.setAttribute("aria-label", name)

    const card = element("div", "flex flex-col overflow-hidden rounded-cs border border-line bg-surface")
    const preview = element("div", "flex aspect-[4/3] w-full flex-col justify-end bg-sunken")
    const bar = element("div", "h-[3px] w-full bg-line")
    bar.dataset.uploadBar = ""
    const fill = element("div", "h-full bg-accent")
    fill.dataset.uploadFill = ""
    fill.style.width = "0%"
    bar.append(fill)
    preview.append(bar)

    const body = element("div", "flex flex-col gap-1 px-2.5 py-2")
    const title = element("span", "truncate text-sm font-medium text-ink")
    title.textContent = name
    const status = element("span", "text-xs text-meta")
    status.dataset.uploadStatus = ""
    status.textContent = TEXTS.uploading
    const dismiss = element("button", "self-start rounded-cs border border-line-strong px-2 py-0.5 text-xs text-ink hover:bg-sunken focus:outline-2 focus:outline-accent")
    dismiss.type = "button"
    dismiss.hidden = true
    dismiss.dataset.uploadDismiss = ""
    dismiss.textContent = TEXTS.dismiss
    dismiss.addEventListener("click", () => this.dismissTile(li))
    body.append(title, status, dismiss)

    card.append(preview, body)
    li.append(card)
    return li
  }

  dismissTile(li) {
    const entry = this.live.find((candidate) => candidate.li === li)
    if (entry) this.dismiss(entry)
  }
}

function element(tag, className) {
  const node = document.createElement(tag)
  node.className = className
  return node
}
