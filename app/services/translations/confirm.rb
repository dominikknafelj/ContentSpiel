module Translations
  # "Mark as up to date" (translation helpers spec §3.4): the original
  # changed, but the translator judged the translation still right. Stores
  # the current original's digest for one field in one language
  # (`Translations::Tracker#confirm_translation`) without touching the value,
  # so the field reads `:current` again. Needs exactly the right an edit of
  # that record would (`Translations::EditRight`), and is recorded as
  # `<subject>.translation_confirmed` with the field and language.
  #
  # The record is a Page, Post, ContentBlock, Media::Asset or the
  # SiteSetting row (its title and tagline).
  class Confirm < ApplicationService
    include EditRight

    EVENT = { "Page" => "page", "Post" => "post", "ContentBlock" => "block", "Media::Asset" => "media",
      "SiteSetting" => "settings" }.freeze

    def initialize(record, field:, locale:, actor: Current.actor)
      @record = record
      @field = field.to_s
      @locale = locale.to_s
      @actor = actor
    end

    def call
      refused = edit_refusal(@record) { |key| authorize!(key, @record) }
      return denied(refused, @record) if refused
      return failure(@record, [ "Nothing to confirm" ]) unless confirmable?

      @record.class.transaction(requires_new: true) do
        @record.confirm_translation(@field, @locale)
        # `update_columns`, not `save`: `translation_sources` is the only
        # thing that changes, and it's bookkeeping -- no callback has
        # anything to do (a page's position and cached paths, a block's
        # owner touch, the usage index), and `updated_at` must not move.
        # The editor's autosave holds the record's `updated_at` as its base
        # (`base_updated_at`), so bumping it here would make the very next
        # keystroke's save report "Changed elsewhere" against nothing but
        # this click.
        @record.update_columns(translation_sources: @record.translation_sources)
        record_event("#{EVENT.fetch(@record.class.name)}.translation_confirmed", subject: @record,
          metadata: { "field" => @field, "locale" => @locale })
      end
      success(@record)
    end

    private

    # A tracked field of this record, in a language that is a translation
    # of the original right now -- never the primary language itself (it
    # can't be outdated against itself) or a disabled one.
    def confirmable?
      @record.class.translation_tracked_fields(@record).include?(@field) && Translations.target_locales.include?(@locale)
    end
  end
end
