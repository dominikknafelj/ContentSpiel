module Admin
  module Shell
    # CS Studio's modules column (design pass spec §4, handoff
    # "StudioSidebar"): the wordmark and the "Jump to..." button, the modules
    # in Content / People / System sections, then the theme switch and the
    # account block. `modules` is `admin_modules` -- already narrowed to what
    # this user may open -- so a section with nothing left in it disappears,
    # heading and all, and a user with no grants sees only the open modules.
    #
    # `url_options` goes on every module link (final-fixes round, finding 5):
    # without it, following a modules link while editing a non-default
    # language silently dropped back to `Locales.default` -- these are the
    # one navigation in the shell that doesn't already run through a
    # component (`Admin::TreeNodeComponent#path`, `Admin::LanguageTabsComponent`,
    # ...) that threads it through for its own links.
    class SidebarComponent < Admin::AdminComponent
      def initialize(modules:, user:, current_path:, url_options:, badges: {})
        @modules = modules
        @user = user
        @current_path = current_path.to_s
        @link_options = url_options
        @badges = badges
      end

      # What the account block says this user is (`AccountIdentityComponent`).
      def role_line = Admin::Shell::AccountIdentityComponent.new(user: user).role_line

      private

      attr_reader :user, :current_path, :link_options, :badges

      # The non-empty groups, in the order `MODULE_GROUPS` declares, each
      # with its modules in `MODULES` order.
      def sections
        Admin::BaseController::MODULE_GROUPS.filter_map do |key, heading|
          entries = @modules.select { |entry| entry[:group] == key }
          [ heading, entries ] if entries.any?
        end
      end

      def module_path(entry) = public_send(entry[:path], **link_options)

      # The module whose own path (without the language param) is this
      # request's path or a parent of it; Dashboard's path is the admin
      # root, a prefix of everything, so it matches only exactly.
      def current?(entry)
        path = public_send(entry[:path])
        return current_path.chomp("/") == path if entry[:path] == :admin_root_path

        current_path == path || current_path.start_with?("#{path}/")
      end

      def link_classes(entry)
        base = "flex items-center gap-2.5 rounded-cs px-2 py-1.5 text-sm hover:bg-sunken"
        current?(entry) ? "#{base} bg-sunken font-medium text-ink" : "#{base} text-dim"
      end

      # An entry's count (notes spec §5): Dashboard's and Trash's today,
      # handed in by the layout as `badges`, keyed by the entry's path helper.
      # Each has a stable id, because a tab fetches the numbers again by
      # itself (`GET admin_unread_notes_path`) and writes them in by id.
      #
      # The Dashboard's element is ALWAYS in the page, `hidden` and empty at
      # zero, because a live signal fills it; Trash's is drawn only when
      # there is something to say, as it always was. An entry not named here
      # has no badge, whatever is handed in.
      BADGE_IDS = { admin_root_path: "sidebar-badge-dashboard", admin_trash_path: "sidebar-badge-trash" }.freeze
      ALWAYS = %i[admin_root_path].freeze

      def badge_count(entry) = badges[entry[:path]].to_i

      def badge?(entry) = BADGE_IDS.key?(entry[:path]) && (badge_count(entry).positive? || ALWAYS.include?(entry[:path]))

      # The Dashboard's is the one FILLED badge of the sidebar (handoff
      # "Sidebar badge"): accent means "unread and addressed to you" and
      # nothing else (notes spec §4.5). Trash's stays the plain mono number.
      def badge_class(entry)
        return "ml-auto rounded-full bg-accent px-1.5 font-cs-mono text-label leading-4 text-on-accent" if entry[:path] == :admin_root_path

        "ml-auto font-cs-mono text-label text-meta"
      end
    end
  end
end
