# CS Studio's modules (`StudioModules`), in the sidebar's order within each
# group. Inside `to_prepare`, like every registry (`config/initializers/
# types.rb`, `admin_slots.rb`): it runs at boot and after each development
# reload, which unloads the registry; it is emptied first, so nothing is
# registered twice. A badge names its classes inside its body, so it reaches
# the ones loaded now.
Rails.application.config.to_prepare do
  StudioModules.reset!

  # CS Studio's home, open to every signed-in user and first: the Pages index
  # sends whoever cannot read pages here (`first_admin_module_path`).
  StudioModules.register :dashboard, icon: :dashboard, path: :admin_root_path, permission: nil, group: :content
  StudioModules.register :pages, icon: :pages, path: :admin_pages_path, permission: "pages.read", group: :content
  StudioModules.register :posts, icon: :posts, family: :lists, path: :admin_posts_path, permission: "posts.read", group: :content
  StudioModules.register :media, icon: :media, family: :media, path: :admin_media_path, permission: "media.upload", group: :content
  # Either right: the list opens for a holder of `form_submissions.view` as
  # well as `forms.manage`. The icon is the Form block's.
  StudioModules.register :forms, icon: :clipboard_list, family: :form, path: :admin_forms_path,
    permission: %w[forms.manage form_submissions.view], group: :content
  # Only with more than one language enabled, a site setting and not a right.
  StudioModules.register :translations, icon: :translations, path: :admin_translations_path, permission: %w[pages.read posts.read],
    group: :content, visible: -> { Locales.enabled.size > 1 }
  StudioModules.register :tags, icon: :tags, path: :admin_tags_path, permission: "tags.manage", group: :content
  # Either read right, as the screen's own gate (`Admin::MindGraphController
  # #require_graph_access`): someone with `pages.read` alone has the link.
  StudioModules.register :mind_graph, icon: :graph, path: :admin_mind_graph_path, permission: %w[pages.read posts.read], group: :content
  # Any one of the rights that act on a trashed item; the screen gates on the
  # same list (`Admin::TrashController#require_trash_access`).
  StudioModules.register :trash, icon: :trash, path: :admin_trash_path, permission: Admin::BaseController::TRASH_PERMISSIONS, group: :content
  StudioModules.register :users, icon: :users, path: :admin_users_path, permission: "users.manage", group: :people
  StudioModules.register :groups, icon: :groups, path: :admin_groups_path, permission: "groups.manage", group: :people
  StudioModules.register :settings, icon: :settings, path: :admin_settings_path, permission: %w[settings.manage languages.manage], group: :system
  # Open to everyone: the screen lists and manages the user's own tokens.
  StudioModules.register :ai_assistant, icon: :assistant, path: :admin_api_tokens_path, permission: nil, group: :system
  StudioModules.register :system_status, icon: :status, path: :admin_system_status_path, permission: "system_status.view", group: :system
  StudioModules.register :audit_log, icon: :audit, path: :admin_audit_events_path, permission: "audit.view", group: :system

  # The viewer's unread notes, on records they may read now: one COUNT on
  # `note_deliveries`, served by its `(user_id, read_at)` index.
  StudioModules.badge(:dashboard) { |viewer:| viewer ? Dashboard::NotesForYou.new(actor: viewer).unread_count : 0 }
  # What the viewer could act on in the trash, the sum of the Trash screen's
  # own tab counts (`Admin::TrashController.badge_count`).
  StudioModules.badge(:trash) { |viewer:| Admin::TrashController.badge_count(viewer) }
end
