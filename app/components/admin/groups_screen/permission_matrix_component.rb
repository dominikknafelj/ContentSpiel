module Admin
  module GroupsScreen
    # The group editor's permissions (access-control design spec §5 "Groups
    # module"; round 3 Task 10 rebuilt it from a checkbox list into rows):
    #
    # - **Content permissions**: every permission that carries a scope, one row
    #   each (`GroupsScreen::PermissionRowComponent`) -- Posts x5, Pages x6 -- under
    #   its area's heading, each with its own scope chips and "Edit scope";
    # - **Other permissions**: the rest, as cards of toggles
    #   (`GroupsScreen::ToggleListComponent`).
    #
    # This component only composes them: it loads what the rows share (the page
    # tree, once for all six pages rows; the notes about stale grants) and decides
    # which rows start open. The posted params did not change:
    #
    #   group[grants][posts.edit][enabled]         "1" when ticked
    #   group[grants][posts.edit][content_types][] type names
    #   group[grants][posts.edit][own]             "1"
    #   group[grants][pages.edit][page_ids][]      branch root ids
    #
    # `grants` is what's ticked now: the group's grants as the editor carries
    # them (`AccessControl::LiveGrants#carried_attributes`: live values plus a
    # removed content type), or the submitted ones when a save failed. `stale` is
    # the group's `LiveGrants`, for the notes on what a save will still drop
    # (Review Focus 3) -- a deleted branch root, a grant that matches nothing any
    # more (shown unticked; see `LiveGrants` for why it can't be shown ticked; one
    # that names only removed content types says that saving removes it and who can
    # manage the group until then, `#dormant_note`), an unregistered permission. A removed content type is no longer a note: it is a
    # chip with Remove inside the row (`ScopeEditorComponent`).
    #
    # `open_keys`: the rows whose scope editor starts open -- after a failed save,
    # the ones the error names, so the editor can see what was refused.
    #
    # A stored branch root the viewer can't read stays in the form as a hidden
    # input (`ScopeEditorComponent`), so saving the group doesn't silently drop it
    # -- and a grant whose only roots were unreadable doesn't turn into an
    # unscoped one.
    #
    # LOCKED TICKS (round 3 Task 11, D15) are DEFENSIVE. A grant the group already
    # STORES that the viewer couldn't hand out themselves (`AccessControl.can_grant?`
    # false on its scope as stored, a removed content type's name included) would be
    # drawn locked: greyed, "You can't grant this", no scope editor, carried by hidden
    # inputs holding the whole scope as stored (`PermissionRowComponent`), so a form
    # saved as rendered changes nothing. But a stored group with such a grant is one
    # the viewer can't manage at all (`can_manage_group?` asks the same question of
    # the same scopes), so it is drawn read-only instead and no stored state is
    # expected to reach the lock; it stays for any state that rule doesn't foresee. It
    # is asked only for a non-owner, once per ticked permission, and ONLY while the
    # row's scope still equals what is stored (`stored:`, the carried scopes): a typed
    # tick -- one on a new group, or one the editor changed, coming back after a
    # refused save (422) -- is never locked, it comes back ticked and editable, since
    # a lock there would make the next Save a guaranteed refusal. The check costs at
    # most one closure-table query for a pages row, never one per page in the tree or
    # per member. `Groups::Save` decides every write; this is only what the form shows
    # and carries.
    #
    # A REMOVED CONTENT TYPE (a warn chip with Remove, `ScopeEditorComponent`) is
    # therefore only ever editable for a viewer who could grant that name: an owner,
    # or someone whose own grant for the permission names no types or names that one.
    # For anyone else the group is view-only -- the name is dormant, not gone, and
    # `can_manage_group?` judges the grants as stored.
    # `view_only:` is a group the viewer can't manage at all: no locks (the whole form
    # is disabled anyway) and the rows' scope toggle becomes a link that survives the
    # disabled fieldset.
    #
    # Showing and hiding the editors and rewriting the chips is
    # `admin--permission-matrix`; the tri-state tree is `admin--branch-picker`.
    class PermissionMatrixComponent < AdminComponent
      def initialize(grants:, stale: nil, form_name: "group[grants]", locale: Locales.default, open_keys: [], tree: nil, view_only: false, stored: [])
        @view_only = view_only
        @stored = Array(stored).to_h { |grant| [ grant[:permission].to_s, AccessControl::LiveGrants.normalize_scope(grant[:scope]) ] }
        @locked = {}
        @grants = Array(grants).to_h { |grant| [ grant[:permission].to_s, grant[:scope].to_h.stringify_keys ] }
        @stale = stale
        @form_name = form_name
        @locale = locale.to_s
        @open_keys = open_keys.to_set
        @tree = tree
      end

      private

      attr_reader :form_name, :locale

      # The scoped permissions by area, in registry order.
      def sections = AccessControl::Permissions.all.reject { |permission| permission.scopes.empty? }.group_by(&:area)

      def tree = @tree ||= GroupsScreen::BranchTree.for(Current.actor, locale: locale)

      def row_for(permission)
        GroupsScreen::PermissionRowComponent.new(permission: permission, scope: @grants[permission.key], tree: permission.scopes.include?(:branch) ? tree : nil,
          open: @open_keys.include?(permission.key), form_name: form_name, locked: locked?(permission), view_only: @view_only)
      end

      # See "LOCKED TICKS" above. Memoised per key: the rows and the footnote ask.
      def locked?(permission)
        # No actor is the trusted console/preview case (the checker lets it through).
        return false if @view_only || Current.actor.nil? || !@grants.key?(permission.key) || AccessControl.owner?(Current.actor)
        return false unless @stored[permission.key] == AccessControl::LiveGrants.normalize_scope(@grants[permission.key])

        @locked.fetch(permission.key) { @locked[permission.key] = !AccessControl.can_grant?(Current.actor, permission.key, @stored[permission.key]) }
      end

      def any_locked? = AccessControl::Permissions.all.any? { |permission| locked?(permission) }

      def locked_toggle_keys = AccessControl::Permissions.all.select { |permission| permission.scopes.empty? && locked?(permission) }.map(&:key)

      # Notes about what saving will drop, for one permission. A removed content
      # type is not among them (it is a chip, `PermissionRowComponent`).
      def stale_notes(permission)
        return [] unless @stale

        entry = @stale.entry_for(permission.key)
        notes = entry ? entry.removed_notes.map { |value| "#{value.upcase_first}: removed when you save." } : []
        @stale.dead_for(permission.key).each do |dead|
          notes << (dead.dormant ? dormant_note(dead) : dead_note(dead))
        end
        notes
      end

      def dead_note(dead)
        what = dead.removed.any? ? dead.removed.to_sentence : "nothing"
        "This permission was limited to #{what}, so it matched nothing. It stays off unless you tick it again."
      end

      # A dead grant that a re-registered content type would bring back
      # (`LiveGrants::Dead#dormant`) is still a right the group stores: it is what
      # makes the group view-only for a manager who couldn't grant that type, with
      # no chip to show for it (the row is unticked). So the note says what clears
      # it. Saving the form does -- the grant is never posted -- which is why the
      # form of such a group has Save enabled from the start (`admin/groups/_form`).
      def dormant_note(dead)
        names = Array(dead.dormant["content_types"]) - AccessControl::Permissions.content_type_choices
        "Limited to a content type that no longer exists (#{names.join(", ")}). Saving removes it; until then only someone who could grant that type can manage this group."
      end

      # Stored grants whose permission key isn't registered any more -- no
      # row to hang them on.
      def unregistered_notes
        return [] unless @stale

        @stale.dead.reject { |dead| AccessControl::Permissions.find(dead.permission) }
          .map { |dead| "The permission “#{dead.permission}” no longer exists and will be removed when you save." }
      end

      def toggle_grants = @grants.slice(*AccessControl::Permissions.all.select { |permission| permission.scopes.empty? }.map(&:key))
    end
  end
end
