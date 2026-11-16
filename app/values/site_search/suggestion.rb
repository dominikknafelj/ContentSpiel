module SiteSearch
  # One title a backend suggests, by what names its copy (search 2 spec
  # §7.2), as a hit does: `record_type`, `record_id`, `copy_id`, and `rank`,
  # a Numeric that orders one answer's items. It carries no text: what is
  # drawn is read again from the copy in force (`SiteSearch::Shown`), so a
  # stale engine names nothing a visitor does not see.
  Suggestion = Data.define(:record_type, :record_id, :copy_id, :rank)
end
