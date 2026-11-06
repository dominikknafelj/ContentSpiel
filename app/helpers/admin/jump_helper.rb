module Admin
  # Turns a ⌘K row's route (`Jump::Search`: `[name, arguments, params]`) into
  # its URL, with the editing language of this request (`admin_url_options`).
  #
  # The name came from a query, which knows no routes, so it reaches
  # `public_send` only if it is one of the destinations a row can have: a
  # page, a post, an image, the Settings sections and the actions
  # (`JUMP_ROUTES`), or a registered module's path (`StudioModules`, whose
  # `path:` symbols the controller hands to the query). Anything else raises:
  # a new kind of row must be added here on purpose, and
  # `jump_controller_test.rb` fails until every route the query can produce
  # is on the list.
  module JumpHelper
    JUMP_ROUTES = %i[
      admin_page_path admin_post_path admin_media_path admin_settings_path
      new_admin_page_path new_admin_post_path admin_account_path
    ].freeze

    # Every route a row may carry: the fixed destinations and the modules'
    # paths, read when asked, so a module registered after boot is on it.
    def self.routes = JUMP_ROUTES | StudioModules.entries.map(&:path)

    def jump_row_path(route)
      name, args, params = route
      raise ArgumentError, "#{name.inspect} is not a route ⌘K may link to (Admin::JumpHelper.routes)" unless Admin::JumpHelper.routes.include?(name)

      public_send(name, *args, **params, **admin_url_options)
    end
  end
end
