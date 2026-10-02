module Translations
  # Where a record stands in each language (translation helpers spec §3.3):
  # `:missing`, `:outdated` or `:complete`, in that order of precedence --
  # a locale missing a required value reads missing even if something else
  # there is also outdated. A field reading `:unknown` (present, saved
  # before tracking existed) counts as complete, so deploying this flags
  # nothing (Review Focus 1).
  #
  # * `:missing` is the required-field rule `Admin::TranslationStatus` had
  #   (cs-studio spec §6.2), moved here unchanged: the record's own title is
  #   blank there, or a required translated schema field of the record or of
  #   any of its content blocks is. Those are exactly the tracked fields a
  #   record can't do without; an optional field left blank (a subtitle, an
  #   image's caption) is a choice, not a gap, and never reads missing.
  #   An image's `alt` plays the title's part (Task 3 ruling): an image is
  #   missing in a language when its original has alt text and that
  #   language has none -- without this, an image could never read missing
  #   (nothing about it is required), and untranslated images would never
  #   surface anywhere. An image without an original alt has nothing to
  #   translate, so it isn't missing anywhere.
  # * `:outdated` is any tracked field of the record, or of its blocks,
  #   reading `:outdated` (`Translations::Tracker#translation_state`).
  #
  # Blocks roll up into their owner: an editor translates a page, not its
  # blocks one by one, so the page's dot is the only place a block's state
  # shows. `.for` loads the blocks of every page/post it's handed in one
  # query -- the lists (Task 4) call it for a whole page of records.
  #
  # Every read is *literal* per locale -- `read_attribute(:title)` (the raw
  # jsonb hash, same as `Page#title_present_in_any_locale`/`Post#
  # title_present_in_any_locale`) and `settings_object(locale:)`/`fields
  # (locale:)` with no `fallback:` -- never `Locales.fallback_chain`. A locale
  # that only *looks* complete because some other locale's value fell back
  # into place is exactly the gap this status exists to surface, not hide.
  module Status
    module_function

    # `{ record => { locale => :complete | :missing | :outdated } }`, keyed
    # by the records handed in, locales as Strings.
    def for(records, locales: Translations.target_locales)
      records = Array(records)
      locales = locales.map(&:to_s)
      blocks = blocks_by_owner(records)

      records.index_with do |record|
        owned = blocks.fetch([ record.class.polymorphic_name, record.id ], [])
        locales.index_with { |code| record_state(record, owned, code) }
      end
    end

    # The codes `Admin::LanguageSwitcherComponent` marks with a dot. Every
    # enabled locale, the primary one included: a page whose own title is
    # blank in the default language is just as much a gap.
    def missing_locales(record) = locales_in(record, :missing, ::Locales.enabled)

    # The primary locale is the original, never outdated against itself.
    def outdated_locales(record) = locales_in(record, :outdated, Translations.target_locales)

    def field_state(record, field, locale) = record.translation_state(field, locale)

    def locales_in(record, state, locales)
      self.for([ record ], locales: locales).fetch(record).select { |_code, value| value == state }.keys
    end

    def record_state(record, blocks, code)
      return :missing if missing?(record, blocks, code)
      return :outdated if ([ record ] + blocks).any? { |item| outdated?(item, code) }

      :complete
    end

    # Only pages and posts own blocks (`ContentBlock#owner`); one query for
    # all of them, never one per record. Records not yet saved own nothing.
    def blocks_by_owner(records)
      owners = records.select { |record| (record.is_a?(Page) || record.is_a?(Post)) && record.persisted? }
      return {} if owners.empty?

      ContentBlock.where(owner: owners).order(:position).group_by { |block| [ block.owner_type, block.owner_id ] }
    end

    def missing?(record, blocks, code)
      case record
      when Page then page_missing?(record, blocks, code)
      when Post then post_missing?(record, blocks, code)
      when Media::Asset then image_missing?(record, code)
      else false
      end
    end

    def outdated?(record, code)
      record.class.translation_tracked_fields(record).any? { |field| record.translation_state(field, code) == :outdated }
    end

    def page_missing?(page, blocks, code)
      title_blank?(page, code) ||
        blocks.any? { |block| required_fields_blank?(block.definition, block.settings_object(locale: code)) }
    end

    def post_missing?(post, blocks, code)
      title_blank?(post, code) || required_fields_blank?(post.definition, post.fields(locale: code)) ||
        blocks.any? { |block| required_fields_blank?(block.definition, block.settings_object(locale: code)) }
    end

    def image_missing?(asset, code)
      alt = asset.read_attribute(:alt).to_h
      alt[Translations.primary_locale].present? && alt[code.to_s].blank?
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

    private_class_method :locales_in, :record_state, :blocks_by_owner, :missing?, :outdated?,
      :page_missing?, :post_missing?, :image_missing?, :title_blank?, :required_fields_blank?
  end
end
