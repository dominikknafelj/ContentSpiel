module Admin
  module GroupsScreen
    # The scope controls of one permission row, opened in place by "Edit scope"
    # (round 3 Task 10): what the old matrix showed under a ticked permission,
    # redrawn --
    #
    # - posts: the content types as a multi-select (none ticked = all) and an
    #   "Own only" toggle ("Only posts the user wrote." -- the rule that exists:
    #   `Scoping` matches `author_id`);
    # - pages: the branch tree, tri-state (`BranchTree`, `admin--branch-picker`).
    #
    # Everything stays in the form whether the editor is open or closed (open and
    # close are only `hidden`), and `GroupsController#grants_from` ignores the
    # scope of an unticked permission -- so opening, closing or never opening an
    # editor changes nothing that is submitted.
    #
    # WHAT IT CARRIES (Review Focus 3, "a form submitted as rendered changes
    # nothing"):
    # - a removed content type: a warn chip with Remove and a hidden input
    #   (`data-save-bar-track`, so pressing Remove is a counted change) -- the
    #   value is submitted until Remove, and `Groups::Save` reads it as a dead
    #   scope value, not a change;
    # - a stored branch root the viewer can't open: a hidden input and the line
    #   "A page you can't open (kept)" under the tree. A context-only ancestor
    #   is in the tree (greyed text, no box) but a chosen one is carried the same
    #   way, so the tree never grows a box that submits it;
    # - neither a partial ancestor nor an implied descendant is ever submitted:
    #   one is unchecked, the other disabled.
    class ScopeEditorComponent < AdminComponent
      NOTE_INCLUDED = "included".freeze
      NOTE_PARTIAL = "contains a chosen page".freeze

      def initialize(permission:, scope:, tree:, id:, open: false, form_name: "group[grants]")
        @permission = permission
        @scope = scope.to_h.stringify_keys
        @tree = tree
        @id = id
        @open = open
        @form_name = form_name
      end

      private

      attr_reader :permission, :scope, :tree, :id, :form_name

      def open? = @open
      def slug = permission.key.tr("./", "--")
      def field_name(*parts) = "#{form_name}[#{permission.key}]" + parts.map { |part| "[#{part}]" }.join
      def field_id(*parts) = [ "grant", slug, *parts ].join("-")

      def types_shown = permission.scopes.include?(:content_type)
      def own_shown = permission.scopes.include?(:own)
      def branch_shown = permission.scopes.include?(:branch) && tree

      def registered_types = AccessControl::Permissions.content_type_choices
      def chosen_types = Array(scope["content_types"])
      def removed_types = chosen_types - registered_types
      def content_type_label(name) = ContentTypes.find(name)&.label || name.to_s.humanize

      def dot_class(name)
        definition = ContentTypes.find(name)
        Ui::ContentTypeDotComponent.new(content_type: name).mark_class(definition.colour_index) if definition
      end

      # --- Branch tree ------------------------------------------------------

      def selected_page_ids = Array(scope["page_ids"]).map(&:to_i)
      def states = @states ||= tree.states(selected_page_ids)
      def kept_page_ids = tree.unreadable(selected_page_ids)

      def note_for(state)
        case state.state
        when :implied then NOTE_INCLUDED
        when :chosen then state.descendants.positive? ? "includes #{helpers.pluralize(state.descendants, "subpage")}" : ""
        when :partial then NOTE_PARTIAL
        else ""
        end
      end

      def mark_for(state)
        { implied: "✓", chosen: "✓", partial: "–" }.fetch(state.state, "")
      end

      def branch_list(ids)
        return "".html_safe if ids.empty?

        tag.ul(class: "flex flex-col") do
          safe_join(ids.map { |page_id| branch_node(page_id) })
        end
      end

      def branch_node(page_id)
        node = tree.node(page_id)
        state = states.fetch(page_id)
        tag.li(class: "admin-branch-node", data: { admin__branch_picker_target: "node", chosen: (state.chosen ? "1" : "") }) do
          row = tag.div(class: "flex items-center gap-2.5 px-2 py-1 text-sm") do
            control = if node.readable
              box_id = field_id("page", page_id)
              tag.label(for: box_id, class: "flex min-w-0 items-center gap-2.5 text-ink") do
                render(Admin::Ui::CheckboxComponent.new(name: field_name("page_ids") + "[]", value: page_id, id: box_id,
                  checked: %i[chosen implied].include?(state.state), disabled: state.state == :implied,
                  data: { admin__branch_picker_target: "box", action: "admin--branch-picker#change", chip_label: node.title, partial: (state.state == :partial || nil) })) + node.title
              end
            else
              tag.span(class: "flex min-w-0 items-center gap-2.5 text-dim", title: "You can't open this page") do
                tag.span(mark_for(state), class: "admin-tri-mark inline-flex h-4 w-4 shrink-0 items-center justify-center rounded-cs border border-line-strong text-xs", aria: { hidden: true }, data: { admin__branch_picker_target: "mark" }) + node.title
              end
            end
            # A root that is chosen AND below another chosen root (a stored state the
            # editor never writes itself: sibling roots, then one moved under the other)
            # has a disabled box, which isn't submitted -- so an untouched save would
            # normalise it away. This carries it, in the row, submitted exactly while it
            # is chosen and implied; `admin--branch-picker#refresh` keeps that in step
            # (the box takes over once the ancestor is unticked, never both). Untracked:
            # a hidden input never counts towards the footer, so nothing here is a change.
            carried = node.readable && state.chosen ? hidden_field_tag(field_name("page_ids") + "[]", page_id, id: nil, disabled: state.state != :implied) : "".html_safe
            control + carried + tag.span(note_for(state), class: "ml-auto text-xs text-meta", data: { admin__branch_picker_target: "note" })
          end
          row + tag.div(branch_list(node.child_ids), class: "ml-5")
        end
      end
    end
  end
end
