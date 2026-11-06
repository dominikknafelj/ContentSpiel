module Admin
  module Shell
    # CS Studio's modules column (design pass spec §4, handoff
    # "StudioSidebar"): the wordmark and the "Jump to..." button, the modules
    # in Content / People / System sections, then the theme switch and the
    # account block. `modules` is `admin_modules`: the rows of the modules
    # registered in `StudioModules`, already narrowed to what this user may
    # see, so a section with nothing left in it disappears, heading and all,
    # and a user with no grants sees only the open modules. This component
    # names no module: what each draws, its badge's style included, is the
    # registry's.
    #
    # Each module's icon stands on its family's chip
    # (`Admin::Ui::IconChipComponent`); its name beside it is the link's
    # accessible name.
    #
    # `url_options` goes on every module link: without it, following a
    # modules link while editing a non-default language would fall back to
    # `Locales.default` -- these are the one navigation in the shell that doesn't already run through a
    # component (`Admin::PagesScreen::TreeRowComponent#path`, `Admin::Ui::LanguageTabsComponent`,
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

      # The non-empty groups, in `StudioModules.groups` order, each headed by
      # its name and holding its modules in registration order.
      def sections
        StudioModules.groups.filter_map do |group|
          entries = @modules.select { |entry| entry[:group] == group }
          [ t("admin.module_groups.#{group}"), entries ] if entries.any?
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

      # A row rests on the column and is sunken under the pointer; the
      # current one stands on the accent tint in accent words, its chip the
      # accent tint too (`chip_family`): a link marked `aria-current`, never
      # a button.
      ROW = "flex items-center gap-2.5 rounded-button px-2 py-1.5 text-sm".freeze

      def link_classes(entry)
        current?(entry) ? "#{ROW} bg-accent-tint font-medium text-accent" : "#{ROW} text-dim hover:bg-sunken hover:text-ink"
      end

      def chip_family(entry) = current?(entry) ? :accent : entry[:family]

      # A module's count, handed in by the layout as `badges` by module name
      # (`admin_module_badges`). A module with a registered badge
      # (`StudioModules.badge`) has its element ALWAYS in the page, by a
      # stable id, `hidden` and empty at zero, because a tab fetches a number
      # again by itself and writes it in by id. A module without one has no
      # badge, whatever is handed in.
      def badge?(entry) = StudioModules.badged?(entry[:name])

      def badge_count(entry) = badges[entry[:name]].to_i

      def badge_id(entry) = "sidebar-badge-#{entry[:name]}"

      # A `:filled` badge (`StudioModules.badge(name, style: :filled)`, the
      # Dashboard's, handoff "Sidebar badge") is the accent pill: accent there
      # means "unread and addressed to you" and nothing else. A `:plain` one
      # is a number in sans.
      def badge_class(entry)
        return "ml-auto rounded-full bg-accent px-1.5 text-count leading-4 text-on-accent" if StudioModules.badge_style(entry[:name]) == :filled

        "ml-auto text-count text-meta"
      end
    end
  end
end
