module Admin
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
  # more (shown unticked; see `LiveGrants` for why it can't be shown ticked), an
  # unregistered permission. A removed content type is no longer a note: it is a
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
  # Showing and hiding the editors and rewriting the chips is
  # `admin--permission-matrix`; the tri-state tree is `admin--branch-picker`.
  class PermissionMatrixComponent < AdminComponent
    def initialize(grants:, stale: nil, form_name: "group[grants]", locale: Locales.default, open_keys: [], tree: nil)
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
        open: @open_keys.include?(permission.key), form_name: form_name)
    end

    # Notes about what saving will drop, for one permission. A removed content
    # type is not among them (it is a chip, `PermissionRowComponent`).
    def stale_notes(permission)
      return [] unless @stale

      entry = @stale.entry_for(permission.key)
      notes = entry ? entry.removed_notes.map { |value| "#{value.upcase_first}: removed when you save." } : []
      @stale.dead_for(permission.key).each do |dead|
        what = dead.removed.any? ? dead.removed.to_sentence : "nothing"
        notes << "This permission was limited to #{what}, so it matched nothing. It stays off unless you tick it again."
      end
      notes
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
