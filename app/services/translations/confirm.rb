module Translations
  # "Still correct — mark up to date" (translation helpers spec §3.4): the original
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
    include ContentBlocks::Structure

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
        # A BLOCK'S CONFIRM TAKES ITS PAGE'S ROW FIRST, as every writer of a
        # page's blocks does (`ContentBlocks::Structure#lock_owner`,
        # `ContentBlocks::Save#call` has the rule and its history). Below,
        # this writes the block's row and then its page's
        # `translation_states` rows -- `StateIndex.refresh` upserts the
        # owner's rows whether or not a value changes, which locks them.
        # `ContentBlocks::Destroy` and `Duplicate` go page, state rows, then
        # OTHER blocks' rows: a delete renumbers the siblings after its
        # refresh, a duplicate's reorder writes every sibling after the
        # copy's save has refreshed. Without the lock a translator confirming
        # a field of block B while another tab removed or copied a section
        # of the same page could hold B and wait for the state rows while
        # that tab held the state rows and waited for B, and Postgres ended
        # one with `ActiveRecord::Deadlocked`, a 500. With it the two queue
        # on the page's row. The shared rows that made the cycle are
        # `translation_states`, not `pages`: this service never writes the
        # page.
        #
        # A page, a post, an image and the settings row need none: the row
        # written first here is the record's own, which is the first row
        # every other writer of that record takes too.
        lock_owner(@record.owner) if @record.is_a?(ContentBlock)
        @record.confirm_translation(@field, @locale)
        # `update_columns`, not `save`: `translation_sources` is the only
        # thing that changes, and it's bookkeeping -- no callback has
        # anything to do (a page's position and cached paths, a block's
        # owner touch, the usage index), and `updated_at` must not move.
        # The editor's autosave holds the record's `updated_at` as its base
        # (`base_updated_at`), so bumping it here would make the very next
        # keystroke's save report "Changed elsewhere" against nothing but
        # this click.
        @record.update_columns(translation_sources: @record.translation_sources) # version: none (bookkeeping no page renders) # changes: none (translation bookkeeping; no change to what a copy shows)
        # The confirmed field no longer counts as outdated in the stored
        # state (`translation_states`); `refresh` writes no `updated_at` on
        # the record either.
        Translations::StateIndex.refresh(@record)
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
