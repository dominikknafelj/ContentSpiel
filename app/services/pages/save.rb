module Pages
  # Creates or updates a page (spec §7.2), the page-tree analogue of
  # `Posts::Save` (Task 8): translations arrive per locale so an admin form
  # can save every language tab at once, and publishing follows the exact
  # rules `Posts::Save` established.
  #
  # Permissions (access-control design spec §3.3), in the same two passes
  # as `Posts::Save` (see its class comment):
  #
  # 1. Before assigning, against the stored page: `pages.edit`, plus
  #    `pages.publish` when it's already published (live or scheduled) --
  #    the spec §8 interim rule that editing live content needs the right
  #    to publish it, until pending revisions (Phase 3).
  # 2. After assigning, inside the transaction: a new page needs
  #    `pages.create` on its *parent's* branch (the checker reads the
  #    assigned `parent`), and any change to `published_at` needs
  #    `pages.publish`. A refusal rolls back and is recorded afterwards.
  #
  # Pages have no author (design spec §8), so there's no `own` rule here.
  class Save < ApplicationService
    TRANSLATED = %i[title slug subtitle meta_title meta_description hero_alt].freeze

    def initialize(page = Page.new, attributes: {}, translations: {}, actor: Current.actor)
      @page = page
      @attributes = attributes.to_h.symbolize_keys
      @translations = translations.to_h
      @actor = actor
    end

    def call
      if @page.persisted?
        return denied("pages.edit", @page) unless authorize!("pages.edit", @page)
        return denied("pages.publish", @page) if @page.published_at.present? && !authorize!("pages.publish", @page)
      end

      refused = nil
      saved = Page.transaction do
        assign
        refused = refusal_after_assign
        raise ActiveRecord::Rollback if refused

        # Captured before saving: closure_tree's own `after_save` reloads
        # the page, clearing `saved_changes` and `previously_new_record?`
        # (see `Audit::Snapshot.field_changes_for`).
        creating = @page.new_record?
        pending = @page.changes_to_save
        @page.save || raise(ActiveRecord::Rollback)
        record_events(creating, Audit::Snapshot.field_changes_for(@page, pending))
        true
      end

      return denied(refused, @page) if refused
      return failure(@page) unless saved

      success(@page)
    end

    private

    # Unlike `Posts::Save`, there's no scope-changing field to re-check
    # `pages.edit`/`pages.publish` against: a page's only scope is its
    # branch, and `parent` is stripped from an update's attributes (see
    # `#assign`) -- a page changes branch only through `Pages::Move`,
    # which checks `pages.create` on the target.
    def refusal_after_assign
      return "pages.create" if @page.new_record? && !authorize!("pages.create", @page)

      "pages.publish" if @page.published_at_changed? && !authorize!("pages.publish", @page)
    end

    # `page.created`/`page.updated`, plus `page.published`/`page.
    # unpublished` when `published_at` changed (see `Posts::Save#record_
    # events` for the shape). The catalogue (design spec §4.3) has no
    # `page.scheduled`: scheduling a page is logged as a `page.updated`
    # whose `field_changes` carry the new `published_at` -- nothing about
    # the live site changes until that moment arrives.
    def record_events(creating, changes)
      if creating
        record_event("page.created", subject: @page, field_changes: changes)
        record_event("page.published", subject: @page, field_changes: changes.slice("published_at")) if @page.live?
      else
        publishing = changes.slice("published_at")
        action = publish_action if publishing.any?
        rest = action ? changes.except("published_at") : changes
        record_event("page.updated", subject: @page, field_changes: rest) if rest.any?
        record_event(action, subject: @page, field_changes: publishing) if action
      end
    end

    # Nil for a page scheduled into the future (see `#record_events`).
    def publish_action
      if @page.published_at.nil? then "page.unpublished"
      elsif @page.live? then "page.published"
      end
    end

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
