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
  #    to publish it, until pending revisions (Phase 3). A publish-state-
  #    only call needs `pages.publish` alone (`#publish_only?`).
  # 2. After assigning, inside the transaction: a new page needs
  #    `pages.create` on its *parent's* branch (the checker reads the
  #    assigned `parent`), and any change to `published_at` needs
  #    `pages.publish`. A refusal rolls back and is recorded afterwards.
  #
  # Pages have no author (design spec §8), so there's no `own` rule here.
  #
  # A page published or scheduled for the first time, or again after an
  # unpublish, also takes its published copy (`Publishing::Version.take!`)
  # in the same transaction; a save of a page that has a time takes none.
  #
  # The hero is a library image (media library design spec §5.1):
  # `hero_media_asset_id` in `attributes` sets, changes or (nil) clears
  # it. Choosing one also needs `media.upload` and an existing asset
  # (`Media::Choosing`). Every save then refreshes the page's own
  # `media_usages` rows inside the transaction (`Media::UsageIndex`). A
  # hero deleted in the meantime fails the save as "doesn't exist".
  #
  # `attributes:` is an allow-list (`ATTRIBUTES`), and any other key is an
  # `ArgumentError` -- a programming error, raised before anything is
  # checked or written, as `Settings::Save` does for a translated key.
  # What isn't on the list isn't this service's to write: `attributes` go
  # straight to `assign_attributes`, so `parent_id` or `position` would
  # move the page around `Pages::Move` (the homepage rule, the
  # own-descendant rule, `pages.move` and `pages.create` on the target),
  # and `trashed_at`, `trashed_by_id` or `trash_root_id` would trash or
  # restore it around `Trash::Move`/`Restore` (the delete right, the
  # branch, the URLs) -- all on the strength of `pages.edit`. No caller
  # passes them (the controllers build the hash from their own short
  # lists); this is what keeps the next one from doing it by accident, and
  # raising rather than dropping the key is what makes such a caller find
  # out. A translated attribute belongs in `translations:` -- here it
  # would land in whatever locale happens to be ambient.
  class Save < ApplicationService
    include Media::Choosing

    TRANSLATED = %i[title slug subtitle meta_title meta_description hero_alt].freeze
    # Everything `attributes:` may carry. `parent` (a `Page`, never
    # `parent_id`) places a NEW page and is dropped on an update (see
    # `#assign`); `published`/`published_at` are the publish state
    # (`#assign_publishing`); the hero goes through `Media::Choosing`. A new
    # page's rank among its siblings is not on the list: it joins at the
    # end, and `Pages::Move` puts it anywhere else.
    ATTRIBUTES = %i[parent page_type hero_media_asset_id published published_at].freeze
    # The attributes a publish-only call may carry (`#publish_only?`).
    PUBLISH_STATE = %i[published published_at].freeze

    def initialize(page = Page.new, attributes: {}, translations: {}, actor: Current.actor)
      @page = page
      @attributes = attributes.to_h.symbolize_keys
      unknown = @attributes.keys - ATTRIBUTES
      raise ArgumentError, "Pages::Save doesn't take #{unknown.join(", ")} in attributes: (see ATTRIBUTES)" if unknown.any?

      @translations = translations.to_h
      @actor = actor
    end

    def call
      if publish_only?
        return denied("pages.publish", @page) unless authorize!("pages.publish", @page)
      elsif @page.persisted?
        return denied("pages.edit", @page) unless authorize!("pages.edit", @page)
        return denied("pages.publish", @page) if @page.published_at.present? && !authorize!("pages.publish", @page)
      end

      hero_refusal = media_choice_result(@page, :hero_media_asset_id, :hero_image)
      return hero_refusal if hero_refusal

      refused = nil
      # `requires_new`: a nested call (starter content) gets its own
      # savepoint, so the FK refusal rescued below can't leave a caller's
      # transaction aborted.
      saved = Page.transaction(requires_new: true) do
        was_unpublished = @page.published_at_in_database.nil?
        assign
        refused = refusal_after_assign
        raise ActiveRecord::Rollback if refused

        # Captured before saving: closure_tree's own `after_save` reloads
        # the page, clearing `saved_changes` and `previously_new_record?`
        # (see `Audit::Snapshot.field_changes_for`).
        creating = @page.new_record?
        pending = @page.changes_to_save
        @page.save || raise(ActiveRecord::Rollback)
        Media::UsageIndex.refresh(@page)
        # Where the page stands in each language (`translation_states`), like
        # the usage rows above: derived inside the same transaction.
        Translations::StateIndex.refresh(@page)
        # Published or scheduled for the first time, or again after an
        # unpublish: the copy the public site will show (drafts spec §4.3).
        # A save of a record that already has a time takes none: its changes
        # wait for `Publishing::PublishChanges`.
        Publishing::Version.take!(@page, by: actor_user) if was_unpublished && @page.published_at.present?
        record_events(creating, Audit::Snapshot.field_changes_for(@page, pending))
        true
      end

      return denied(refused, @page) if refused
      return failure(@page) unless saved

      success(@page)
    rescue ActiveRecord::InvalidForeignKey => e
      # The hero was deleted between `#media_choice_result`'s check and the
      # save (final fix wave, M1; `Media::Choosing`).
      vanished_media_failure(e, @page, :hero_media_asset_id, :hero_image)
    rescue ActiveRecord::RecordNotUnique => e
      # Two creates racing on an empty site both passed `only_one_root_page`;
      # the partial unique index (`index_pages_on_single_root`) let one win.
      # The loser fails like the validation it raced. Any other uniqueness
      # violation is not ours to hide.
      raise unless e.message.include?("index_pages_on_single_root")

      @page.errors.add(:base, "a root page already exists")
      failure(@page)
    end

    private

    # Publishing, unpublishing and scheduling need `pages.publish` (design
    # spec §3.3), not `pages.edit` as well (final fix wave, Important 1):
    # a call on a stored record whose only request is the publish state --
    # `published`/`published_at` and nothing else, no translation values
    # (MCP's `update_post(published:)` sends an empty per-locale hash),
    # no other attribute -- is judged on `publish` alone, so a
    # "Publishers" group (read + publish) can use the header's buttons.
    # Anything more keeps the ordinary rules above: pass 1's edit (+
    # publish when already published), and pass 2's publish check on the
    # new `published_at`, which runs here too and is what actually guards
    # the change.
    def publish_only?
      @page.persisted? && @attributes.any? && (@attributes.keys - PUBLISH_STATE).empty? &&
        @translations.values.all? { |values| values.to_h.empty? }
    end

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
