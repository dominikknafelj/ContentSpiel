// The editor's reservations (live-editing spec §4): claims a block, a page's
// settings or a post when the person starts changing it, releases it, hands
// it over, and makes a form read-only when someone else holds it. Task 9
// fills this in; until then the file exists so that the event the live
// script listens to (`admin--editing--hold:refresh`, `detail: { subject,
// discard }`) names a controller, as `test/lib/source_layout_test.rb` asks.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
}
