module Pages
  # Creates or updates a page (spec §7.2), the page-tree analogue of
  # `Posts::Save` (Task 8): translations arrive per locale so an admin form
  # can save every language tab at once, and publishing follows the exact
  # rules `Posts::Save` established.
  class Save < ApplicationService
    TRANSLATED = %i[title slug subtitle meta_title meta_description hero_alt].freeze

    def initialize(page = Page.new, attributes: {}, translations: {}, actor: Current.actor)
      @page = page
      @attributes = attributes.to_h.symbolize_keys
      @translations = translations.to_h
      # Not read anywhere yet -- the attachment point for `authorize!`/
      # `record_event` once those grow teeth (sub-project 5).
      @actor = actor
    end

    def call
      authorize!(:save, @page)

      saved = Page.transaction do
        assign
        @page.save || raise(ActiveRecord::Rollback)
      end

      return failure(@page) unless saved

      record_event(:page_saved, page: @page)
      success(@page)
    end

    private

    def assign
      @translations.each do |locale, values|
        Mobility.with_locale(locale) { @page.assign_attributes(values.to_h.symbolize_keys.slice(*TRANSLATED)) }
      end

      # `parent` only makes sense on create: moving an already-persisted page
      # to a different parent has its own rules (the homepage can't move, a
      # page can't become its own ancestor) that live in `Pages::Move`, not
      # here -- so an ordinary content save can't smuggle a move through the
      # attributes hash just because a stale `parent` happened to be in it.
      plain = @attributes.except(:published, :published_at)
      plain = plain.except(:parent) if @page.persisted?
      @page.assign_attributes(plain)

      assign_publishing
    end

    # `published_at` schedules explicitly and wins; `published: true` makes a
    # draft or scheduled page live now but keeps a live page's date (spec
    # §7.2, same as `Posts::Save`); `published: false` unpublishes; absent
    # leaves it alone.
    def assign_publishing
      if @attributes.key?(:published_at)
        @page.published_at = @attributes[:published_at]
      elsif @attributes[:published] == true
        @page.published_at = Time.current unless @page.live?
      elsif @attributes[:published] == false
        @page.published_at = nil
      end
    end
  end
end
