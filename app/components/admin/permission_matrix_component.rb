module Admin
  # The group editor's permission matrix (access-control design spec §5
  # "Groups module"): every registered permission, grouped by `area`, as a
  # checkbox; a ticked *scoped* permission shows its scope controls --
  #
  # - content types (`content_type` scope): one checkbox per registered
  #   type, read live from `ContentTypes` (`Permissions.content_type_
  #   choices`), so a plugin's type appears without a code change;
  # - "Own only" (`own`);
  # - a page-branch picker (`branch`): the page tree with a checkbox per
  #   page, storing the ticked pages as branch roots (`page_ids`).
  #
  # Nothing ticked in a scope control means "no restriction" on that
  # dimension, which is what a grant without the key means.
  #
  # Params, per permission key (dots and slashes and all), under
  # `form_name` -- `Admin::GroupsController#grants_from` reads them back:
  #
  #   group[grants][posts.edit][enabled]         "1" when ticked
  #   group[grants][posts.edit][content_types][] type names
  #   group[grants][posts.edit][own]             "1"
  #   group[grants][pages.edit][page_ids][]      branch root ids
  #
  # `grants` is what's ticked now: the group's live grants
  # (`AccessControl::LiveGrants#attributes`), or the submitted ones when a
  # save failed. `stale` is the group's `LiveGrants` for the notes on what
  # a save will drop (Review Focus 3) -- a deleted branch root, an
  # unregistered content type, a whole grant that matches nothing any more
  # (shown unticked; see `LiveGrants` for why it can't be shown ticked).
  #
  # The branch picker only lists pages the actor can read
  # (`AccessControl.tree_visibility`), with their unreadable ancestors as
  # greyed-out context and no checkbox. A stored root the actor can't read
  # stays in the form as a hidden input, shown as "a page you can't open",
  # so saving the group doesn't silently drop it -- and a grant whose only
  # roots were unreadable doesn't turn into an unscoped one.
  #
  # Showing and hiding the scope controls is `admin--permission-matrix`;
  # the implied-branch logic (a page under a ticked page is covered by it,
  # so it's shown ticked, disabled, and never submitted as a root of its
  # own) is `admin--branch-picker`.
  class PermissionMatrixComponent < AdminComponent
    SCOPE_LABELS = { content_type: "Content types", own: "Own only", branch: "Branches" }.freeze

    def initialize(grants:, stale: nil, form_name: "group[grants]", locale: Locales.default)
      @grants = Array(grants).to_h { |grant| [ grant[:permission].to_s, grant[:scope].to_h.stringify_keys ] }
      @stale = stale
      @form_name = form_name
      @locale = locale.to_s
    end

    private

    attr_reader :form_name, :locale

    def areas = AccessControl::Permissions.all.group_by(&:area)

    def ticked?(permission) = @grants.key?(permission.key)
    def scope_for(permission) = @grants.fetch(permission.key, {})

    def field_name(permission, *parts) = "#{form_name}[#{permission.key}]" + parts.map { |part| "[#{part}]" }.join
    def field_id(permission, *parts) = [ "grant", permission.key.tr("./", "--"), *parts ].join("-")

    def content_type_choices = AccessControl::Permissions.content_type_choices

    def content_type_label(name) = ContentTypes.find(name)&.label || name.to_s.humanize

    # Notes about what saving will drop, for one permission.
    def stale_notes(permission)
      return [] unless @stale

      entry = @stale.entry_for(permission.key)
      notes = entry ? entry.removed.map { |value| "#{value.upcase_first}: removed when you save." } : []
      @stale.dead_for(permission.key).each do |dead|
        what = dead.removed.any? ? dead.removed.to_sentence : "nothing"
        notes << "This permission was limited to #{what}, so it matched nothing. It stays off unless you tick it again."
      end
      notes
    end

    # Stored grants whose permission key isn't registered any more -- no
    # row in the matrix to hang them on.
    def unregistered_notes
      return [] unless @stale

      @stale.dead.reject { |dead| AccessControl::Permissions.find(dead.permission) }
        .map { |dead| "The permission “#{dead.permission}” no longer exists and will be removed when you save." }
    end

    # --- The branch picker's tree, loaded once for every `branch` row ---------

    def tree
      @tree ||= begin
        visibility = AccessControl.tree_visibility(Current.actor)
        visible = visibility[:readable] | visibility[:context_only]
        pages = Page.where(id: visible.to_a).order(:position, :id).to_a
        { readable: visibility[:readable], children: pages.group_by(&:parent_id), roots: pages.select { |page| page.parent_id.nil? || !visible.include?(page.parent_id) } }
      end
    end

    def page_title(page) = ::Locales.read(page, :title, locale: locale).presence || "(untitled)"

    # Stored roots the picker can't show -- kept as hidden inputs.
    def hidden_page_ids(permission)
      Array(scope_for(permission)["page_ids"]).map(&:to_i).reject { |id| tree[:readable].include?(id) }
    end

    def selected_page_ids(permission) = Array(scope_for(permission)["page_ids"]).map(&:to_i)

    def branch_summary(permission)
      count = selected_page_ids(permission).size
      count.zero? ? "All pages" : helpers.pluralize(count, "branch")
    end

    # The nested checkbox list, recursively. Readable pages get a checkbox;
    # context-only ancestors are plain, greyed-out text.
    def branch_list(permission, pages)
      return "".html_safe if pages.empty?

      selected = selected_page_ids(permission)
      tag.ul(class: "ml-4 flex flex-col gap-1 first:ml-0") do
        safe_join(pages.map do |page|
          tag.li(data: { admin__branch_picker_target: "node" }) do
            row =
              if tree[:readable].include?(page.id)
                id = field_id(permission, "page", page.id)
                tag.label(for: id, class: "flex items-center gap-2 text-ink") do
                  render(Admin::CheckboxComponent.new(name: field_name(permission, "page_ids") + "[]", value: page.id, checked: selected.include?(page.id), id: id,
                    data: { admin__branch_picker_target: "box", action: "admin--branch-picker#change" })) + page_title(page)
                end
              else
                tag.span(page_title(page), class: "block text-dim", title: "You can't open this page")
              end
            row + branch_list(permission, tree[:children].fetch(page.id, []))
          end
        end)
      end
    end
  end
end
