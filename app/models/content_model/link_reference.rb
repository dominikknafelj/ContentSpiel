module ContentModel
  # What a `:link` field holds when it names a page or a post rather than an
  # address (#145; `docs/reference/theme-choices.md`, "A link that follows a
  # page"): the string `cs:page/12` or `cs:post/12`, the spelling rich text's
  # Markdown already gives an `internalLink` (`RichText::BuiltIns`), so the
  # application has one way to write "that record" as text. A string, because a
  # `:link` is one string in `settings` as it always was: the form's one input,
  # a copy, a duplicate, a discard and MCP carry it with no migration and no
  # second shape.
  #
  # `cs:` is on no list of schemes `FieldTypes.link?` accepts, on purpose, and
  # stays off it: `link?` says what a browser may follow, and a reference is
  # never handed to a browser. Whatever reads a stored value asks
  # `PublicSite::Urls#link_for`; a reader that still asks `link?` alone draws
  # no link, which is the safe way to be wrong.
  #
  # Strict by shape: lowercase, no sign, no leading zero, `\A…\z` so a line
  # break is not a way past it, and at most 18 digits so an id always fits the
  # column's bigint. `parse` is total over any value and raises nothing.
  LinkReference = Data.define(:type, :id)

  class LinkReference
    FORMAT = %r{\Acs:(page|post)/([1-9][0-9]{0,17})\z}

    def self.parse(value)
      return nil unless value.is_a?(String) && value.encoding == Encoding::UTF_8 && value.valid_encoding?

      match = FORMAT.match(value)
      match && new(type: match[1], id: match[2].to_i)
    end
  end
end
