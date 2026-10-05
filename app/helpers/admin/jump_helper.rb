module Admin
  # Turns a ⌘K row's route (`Jump::Search`: `[name, arguments, params]`) into
  # its URL, with the editing language of this request (`admin_url_options`).
  #
  # The name came from a query, which knows no routes, so it reaches
  # `public_send` only if it is on this fixed list -- the destinations a row can
  # have (a page, a post, an image, the Settings sections, the actions) and
  # CS Studio's own modules (`Admin::BaseController::MODULES`, whose `path:`
  # symbols the controller hands to the query). Anything else raises: a new
  # kind of row must be added here on purpose, and `jump_controller_test.rb`
  # fails until every route the query can produce is on it.
  module JumpHelper
    JUMP_ROUTES = %i[
      admin_page_path admin_post_path admin_media_path admin_settings_path
      new_admin_page_path new_admin_post_path admin_account_password_path
      admin_root_path admin_pages_path admin_posts_path admin_translations_path admin_tags_path
      admin_mind_graph_path admin_trash_path admin_users_path admin_groups_path
      admin_api_tokens_path admin_system_status_path admin_audit_events_path
    ].freeze

    def jump_row_path(route)
      name, args, params = route
      raise ArgumentError, "#{name.inspect} is not a route ⌘K may link to (Admin::JumpHelper::JUMP_ROUTES)" unless JUMP_ROUTES.include?(name)

      public_send(name, *args, **params, **admin_url_options)
    end
  end
end
