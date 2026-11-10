module Admin
  module GroupsScreen
    # One of the group editor's eleven rows (Posts x5, Pages x6; scopes are
    # per permission): a checkbox, the short label, the key in mono, the scope
    # as chips at the right, and "Edit scope", which opens this row's own
    # `ScopeEditorComponent` in place, indented to the label column.
    #
    # A row is any registered permission that carries a scope (`Permission#
    # scopes`), whatever its area -- the built-ins are the two areas Posts and
    # Pages, a plugin's scoped permission gets a band of its own. An unscoped
    # permission is a switch instead (`ToggleListComponent`).
    #
    # THE PARAMS: `group[grants][<key>][enabled|content_types[]|own|page_ids[]]`,
    # exactly what `Admin::GroupsController#grants_from` reads. Everything else
    # is presentation, plus the two things the editor carries so that a form
    # submitted as rendered changes nothing: a removed content type (a hidden
    # input, until Remove) and a stored branch root the viewer can't open (a
    # hidden input, until nobody).
    #
    # TWO STATES (both presentation: the params above are the same, and
    # `Groups::Save` is still the one that decides):
    #
    # - LOCKED (`locked:`, an editable form whose viewer couldn't hand this grant
    #   out): a ticked, disabled box in the disabled look (no opacity of its own:
    #   the tick keeps its colour and the label beside it turns meta) with "You
    #   can't grant this", the chips as a plain reading of the scope, and NO
    #   "Edit scope" and no scope editor -- nothing here can be unticked or
    #   narrowed. A disabled box isn't submitted, so the row CARRIES the grant:
    #   `enabled` and its whole scope as hidden inputs after the label, exactly as
    #   stored (content types including a removed one, `own`, page ids including
    #   an unreadable or a redundant root). A form saved as rendered therefore
    #   posts it back identically. A forged request that unticks or narrows it is
    #   `Groups::Save`'s call: lawful narrowing is allowed for someone who can
    #   manage the group, anything else is a 403. Defensive: no stored state
    #   reaches it (see `GroupsScreen::PermissionMatrixComponent`).
    # - VIEW ONLY (`view_only:`, a group the viewer can't manage as it stands): the
    #   whole form sits in a `<fieldset disabled>`, which would disable "Edit
    #   scope" too, and a scope is still worth reading. So the toggle is an
    #   `<a role="button">` -- not a form control, so a disabled fieldset leaves it
    #   alone -- that opens the row's own editor (every control in it disabled).
    #
    # SHORT LABELS ("Read", "Move to trash", `.short.<action>`) are this
    # component's own words for a row under its "Posts"/"Pages" band. The
    # registry's labels ("Delete posts") are untouched: the denial copy ("You
    # don't have permission to delete posts") and the checkbox's accessible name
    # (`aria-label`) still use them, and the key sits beside the label in mono
    # with itself as title.
    #
    # THE CHIPS are drawn here for the first paint and by
    # `admin--groups--permission-matrix` after every change: the same rules
    # and words in both (`#chips` / `rewriteChips`), and the same class
    # strings, which the script takes from the matrix (`.chip_classes`). A
    # chip is a neutral badge (a type's with its dot as the badge's mark), a
    # removed type's a warn badge, and "All pages" / "All content types" plain
    # dim words.
    #
    # NO SCRIPT: the scope editor is rendered open and "Edit scope" is held back
    # (`hidden`); the controller closes the editors and shows the buttons on
    # connect. So with scripts off every scope control is on the page.
    class PermissionRowComponent < AdminComponent
      SHORT_LABELS = %i[read create edit publish move delete].freeze
      MAX_CHIPS = 3
      CHIP_CLASS = "admin-scope-chip".freeze
      ALL_CLASS = "admin-scope-chip text-small text-dim".freeze
      DOT_CLASS = "h-[7px] w-[7px] shrink-0 rounded-full".freeze

      # `kind`: :plain, :dim (the "All ..." default), :more ("+N") or :warn.
      Chip = Data.define(:label, :kind, :dot)

      # The class strings a chip is drawn with, by kind, as `BadgeComponent`
      # draws its tones with `CHIP_CLASS` added; the script draws its chips
      # with these.
      def self.chip_classes
        badge = ->(tone) { [ Ui::BadgeComponent::CLASS, Ui::BadgeComponent::TONES.fetch(tone), CHIP_CLASS ].join(" ") }
        { neutral_chip: badge.(:neutral), warn_chip: badge.(:warn), all_chip: ALL_CLASS, dot: DOT_CLASS }
      end

      def initialize(permission:, scope: nil, tree: nil, open: false, form_name: "group[grants]", locked: false, view_only: false)
        @permission = permission
        @locked = locked
        @view_only = view_only
        @scope = scope&.to_h&.stringify_keys
        @tree = tree
        @open = open
        @form_name = form_name
      end

      # The checkbox's accessible name: the registry's full label, which names
      # the subject ("Edit pages"). It has to CONTAIN what the row shows (speech
      # input finds a control by its visible words): "Move to trash" is not in
      # "Delete posts", so that row is "Move to trash: Delete posts".
      def accessible_label
        permission.label.downcase.include?(short_label.downcase) ? permission.label : t(".accessible_label", short: short_label, label: permission.label)
      end

      private

      attr_reader :permission, :scope, :tree, :form_name

      def ticked? = !scope.nil?
      def locked? = @locked && ticked?
      def view_only? = @view_only
      def open? = @open && ticked? && !locked?
      def short_label = SHORT_LABELS.include?(permission.action) ? t(".short.#{permission.action}") : permission.label
      def slug = permission.key.tr("./", "--")
      def checkbox_id = "grant-#{slug}-enabled"
      def editor_id = "scope-editor-#{slug}"
      def field_name(*parts) = "#{form_name}[#{permission.key}]" + parts.map { |part| "[#{part}]" }.join

      # The inputs a locked row carries, as `[name, value]` pairs: the whole scope as stored.
      def carried_inputs
        pairs = [ [ field_name("enabled"), "1" ] ]
        pairs += stored("content_types").map { |name| [ field_name("content_types") + "[]", name ] }
        pairs << [ field_name("own"), "1" ] if scope["own"] == true
        pairs + stored("page_ids").map { |id| [ field_name("page_ids") + "[]", id ] }
      end

      def stored(key) = Array((scope || {})[key])
      def stored_page_ids = stored("page_ids").map(&:to_i)

      def editor
        ScopeEditorComponent.new(permission: permission, scope: scope || {}, tree: tree, id: editor_id, open: open?, form_name: form_name)
      end

      def types_shown = permission.scopes.include?(:content_type)
      def branch_shown = permission.scopes.include?(:branch)

      def registered_types = AccessControl::Permissions.content_type_choices
      def live_types = registered_types & stored("content_types")
      def removed_types = stored("content_types") - registered_types

      # The row's scope in words, in the order the controls come in the editor.
      # Nothing at all while the row is unticked.
      def chips
        return [] unless ticked?

        items = branch_shown ? branch_items : type_items
        # Nothing live ticked is "all", which is what Save stores even while a removed
        # type is still carried (`GroupsController#grants_from`), so the chip says so
        # and the warn chips follow it.
        shown = items.empty? ? [ Chip.new(label: t(branch_shown ? ".chips.all_pages" : ".chips.all_types"), kind: :dim, dot: nil) ] : items.first(MAX_CHIPS)
        shown << Chip.new(label: t(".chips.more", count: items.size - MAX_CHIPS), kind: :more, dot: nil) if items.size > MAX_CHIPS
        shown + removed_types.sort.map { |name| Chip.new(label: t(".chips.removed_type", name: name), kind: :warn, dot: nil) }
      end

      def type_items
        items = live_types.map { |name| Chip.new(label: ContentTypes.find(name)&.label || name.humanize, kind: :plain, dot: dot_class(name)) } # i18n-ok: a type with no definition shows its stored name, as the scope editor's box does
        items << Chip.new(label: t(".chips.own_only"), kind: :plain, dot: nil) if permission.scopes.include?(:own) && scope["own"] == true
        items
      end

      def branch_items
        return [] unless tree

        states = tree.states(stored_page_ids)
        roots = states.select { |_id, state| state.state == :chosen && tree.readable?(_id) }.keys
        items = roots.map { |id| Chip.new(label: t(".chips.under", title: tree.title(id)), kind: :plain, dot: nil) }
        items + tree.unreadable(stored_page_ids).map { Chip.new(label: t(".chips.unreadable"), kind: :plain, dot: nil) }
      end

      def dot_class(name)
        definition = ContentTypes.find(name)
        Ui::ContentTypeDotComponent.new(content_type: name).mark_class(definition.colour_index) if definition
      end

      def render_chip(chip)
        return tag.span(chip.label, class: ALL_CLASS) if chip.kind == :dim

        render(Admin::Ui::BadgeComponent.new(label: chip.label, tone: chip.kind == :warn ? :warn : :neutral, class: CHIP_CLASS)) do |badge|
          badge.with_mark { tag.span(class: "#{DOT_CLASS} #{chip.dot}") } if chip.dot
        end
      end
    end
  end
end
