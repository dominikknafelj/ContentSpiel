module Admin
  # Which enabled locales are missing a *required* translation (cs-studio
  # spec §6.2): the set `Admin::LanguageSwitcherComponent`'s own `missing:`
  # marks with a dot. A locale counts as missing when either the record's own
  # title is blank there, or -- for a page -- any of its content blocks'
  # required translated schema fields are blank there, or -- for a post --
  # any of its content type's required translated schema fields are.
  #
  # Every read is *literal* per locale -- `read_attribute(:title)` (the raw
  # jsonb hash, same as `Page#title_present_in_any_locale`/`Post#
  # title_present_in_any_locale`) and `settings_object(locale:)`/`fields
  # (locale:)` with no `fallback:` -- never `Locales.fallback_chain`. A locale
  # that only *looks* complete because some other locale's value fell back
  # into place is exactly the gap this dot exists to surface, not hide.
  module TranslationStatus
    module_function

    def missing_locales(record)
      case record
      when Page then ::Locales.enabled.select { |code| page_missing?(record, code) }
      when Post then ::Locales.enabled.select { |code| post_missing?(record, code) }
      else []
      end
    end

    def page_missing?(page, code)
      title_blank?(page, code) ||
        page.content_blocks.any? { |block| required_fields_blank?(block.definition, block.settings_object(locale: code)) }
    end

    def post_missing?(post, code)
      title_blank?(post, code) || required_fields_blank?(post.definition, post.fields(locale: code))
    end

    def title_blank?(record, code) = record.read_attribute(:title).to_h[code.to_s].blank?

    # `definition`/`object` are handed in already resolved (a block's own
    # `.definition`, `settings_object(locale:)`/`fields(locale:)`) rather than
    # re-derived here, so this one predicate covers both a page's blocks and
    # a post's own schema fields -- both `nil` for the same reason (an
    # unregistered `block_type`/`content_type`, spec §8), which has nothing
    # here to call "missing": there's no schema left to name a required
    # translated field against.
    def required_fields_blank?(definition, object)
      return false if definition.nil? || object.nil?

      definition.fields.any? { |field| field.required? && field.translated? && object.public_send(field.name).blank? }
    end
  end
end
