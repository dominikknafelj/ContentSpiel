# Searching a translated `title` (a jsonb of { locale => text }, Mobility's
# backend) by a piece of text an editor typed -- the two ways CS Studio does
# it, spelled once. Filtering a jsonb column with a plain `where(title: ...)`
# would compare jsonb to text and never match a row (CLAUDE.md's Mobility
# note); these are the forms that work.
#
# Both match case-insensitively (`ILIKE`, Arel's `matches`) anywhere in the
# title, and both escape the text themselves (`SqlNodes.like_pattern`), so a
# typed `%` or `_` is a character to find, not a wildcard: a caller hands over
# the text as typed and must not escape it again.
#
# Neither narrows by trash state or by what a viewer may read: they are used
# on a relation that `AccessControl.scope` has already narrowed.
module TitleSearch
  extend ActiveSupport::Concern

  included do
    # The records whose title IN THIS LANGUAGE contains the text
    # (`title ->> 'de' ILIKE '%text%'`). Literal per language: no fallback, so
    # a record with no title in `locale` is never matched through another
    # language's.
    scope :title_matching, ->(text, locale:) {
      where(SqlNodes.json_text(arel_table[:title], locale).matches(SqlNodes.like_pattern(text)))
    }

    # The records whose title in ANY language contains the text.
    # `jsonb_each_text` unnests the column so ILIKE tests only the VALUES
    # (`SqlNodes.any_json_value`): `title::text ILIKE` would also match a
    # locale key ("de", "en") or JSON punctuation, and would miss a title
    # containing `"` or `\` (jsonb's text form escapes both).
    scope :title_matching_any_locale, ->(text) {
      where(SqlNodes.any_json_value(arel_table[:title]) { |value| value.matches(SqlNodes.like_pattern(text)) })
    }
  end
end
