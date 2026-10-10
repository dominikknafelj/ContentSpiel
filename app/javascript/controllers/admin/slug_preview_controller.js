import { Controller } from "@hotwired/stimulus"

// Keeps `Admin::Columns::SlugColumnComponent`'s URL preview live as either
// the title or the slug field is typed (cs-studio spec §5.1 -- carried in
// from Task 2's review, where the preview line was still a load-time
// snapshot with nothing to keep it current). Wraps both fields in
// `Admin::EditorScreen::PageSettingsFormComponent`'s own markup, so a plain bubbling
// `input` listener at that shared ancestor is enough; no Stimulus target
// lives outside it.
//
// The slug shown here is a client-side approximation of
// `LocalizedSlug#slugify`'s ASCII fast path -- good enough for a preview,
// but not the value that actually gets saved. The real slug is still
// whatever `Pages::Save` -> `LocalizedSlug#fill_blank_slugs` computes
// server-side on save (including its Unicode-preserving fallback for a
// title with no Latin letters at all), and this controller never writes
// back into the slug input itself -- only the read-only `output` span
// beside it.
export default class extends Controller {
  static targets = ["title", "slug", "output"]

  update() {
    const typed = this.hasSlugTarget ? this.slugTarget.value.trim() : ""
    this.outputTarget.textContent = typed !== "" ? typed : this.slugify(this.hasTitleTarget ? this.titleTarget.value : "")
  }

  slugify(value) {
    return slugify(value)
  }
}

// Exported for `admin--new-record`, whose URL line must read exactly like this one.
export function slugify(value) {
  return value
    .toString()
    .trim()
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
}
