# A row or tile that presses as one through its title's stretched link
# (`Admin::DashboardScreen::WaitingRowComponent`, `DraftTileComponent`). A
# screen reader meets that ONE link, named by the title and the row's
# reasons and described by its verb, and reads none of it a second time: the
# reasons' marks and the verb are drawn beside the link for the eye and are
# `aria-hidden`, and the link names them by id. A hidden element named by
# `aria-labelledby` or `aria-describedby` still gives its words, so hiding
# the mark takes it out of the reading order only.
#
# The including component defines `verb_id`, the id of its verb.
module Admin::DashboardScreen::OneLink
  private

  # The link's `aria:` attributes. `reason_ids` are the ids of the hidden
  # marks that say why the row is listed; the link's own id comes first in
  # its `aria-labelledby`, so its title leads the name. With no reasons the
  # name is the link's text, and with `verb: false` (a row whose verb is a
  # link of its own) it has no description.
  def one_link_aria(link_id: nil, reason_ids: [], verb: true)
    { labelledby: ([ link_id, *reason_ids ].join(" ") if reason_ids.any?), describedby: (verb_id if verb) }
  end

  # The verb at the row's end: words, dim at rest (`.admin-row-verb`), the
  # link's description, and hidden from the reading order.
  def row_verb(text) = tag.span(text, id: verb_id, class: "admin-row-verb", aria: { hidden: true })
end
