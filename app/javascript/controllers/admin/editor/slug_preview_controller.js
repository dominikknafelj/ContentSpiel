import { Controller } from "@hotwired/stimulus"

// Makes the slug field's placeholder say the slug the title will give, from
// the moment the editor opens and as the title is typed. The placeholder carries
// the one job the line under the field had.
//
// The slug shown is a client-side approximation of `LocalizedSlug#slugify`'s
// ASCII fast path -- good enough for a hint, but not the value that gets saved.
// The real slug is still whatever `Pages::Save` -> `LocalizedSlug#fill_blank_slugs`
// computes server-side on save (including its Unicode-preserving fallback for a
// title with no Latin letters at all), and this controller writes nothing but the
// placeholder. `connect` runs again whenever a live refresh replaces the form, so a
// refreshed form has its placeholder too.
export default class extends Controller {
  static targets = ["title", "slug"]

  connect() {
    this.update()
  }

  update() {
    if (!this.hasTitleTarget || !this.hasSlugTarget) return
    this.slugTarget.placeholder = this.slugify(this.titleTarget.value)
  }

  slugify(value) {
    return slugify(value)
  }
}

// Exported for `admin--editor--new-record`, whose URL line must read exactly like this one.
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
