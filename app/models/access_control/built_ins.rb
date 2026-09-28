# Registers every built-in permission (design spec §3.1 / Global
# Constraints) against `AccessControl::Permissions`, the same `.register`
# call a plugin will use later under a prefixed `owner/name` key. Called
# from `config/initializers/types.rb`'s `to_prepare`, right after
# `AccessControl::Permissions.reset!` -- see that initializer for why (a
# code reload in development must re-register cleanly, not raise
# `AccessControl::DuplicatePermission` against whatever's still sitting in
# the registry from before the reload).
#
# Grouped by area, matching the table in design spec §3.1 exactly: `Posts`
# permissions carry `content_type`/`own` scopes, `Pages` permissions carry
# `branch`, and `Content`/`Administration` permissions are unscoped
# (there's exactly one of each -- a grant either holds them or it doesn't).
module AccessControl
  module BuiltIns
    def self.register
      register_posts
      register_pages
      register_content
      register_administration
    end

    def self.register_posts
      scopes = %i[content_type own]

      Permissions.register "posts.read", label: "Read posts", area: "Posts", subject: Post, action: :read, scopes: scopes
      Permissions.register "posts.create", label: "Create posts", area: "Posts", subject: Post, action: :create, scopes: scopes
      Permissions.register "posts.edit", label: "Edit posts", area: "Posts", subject: Post, action: :edit, scopes: scopes
      Permissions.register "posts.publish", label: "Publish posts", area: "Posts", subject: Post, action: :publish, scopes: scopes
      Permissions.register "posts.delete", label: "Delete posts", area: "Posts", subject: Post, action: :delete, scopes: scopes
    end

    # Pages have no author column (design spec §8: "pages have no author,
    # so there is no 'own' scope for pages"), so every page permission
    # carries `branch` alone, never `own`.
    def self.register_pages
      scopes = %i[branch]

      Permissions.register "pages.read", label: "Read pages", area: "Pages", subject: Page, action: :read, scopes: scopes
      Permissions.register "pages.create", label: "Create pages", area: "Pages", subject: Page, action: :create, scopes: scopes
      Permissions.register "pages.edit", label: "Edit pages", area: "Pages", subject: Page, action: :edit, scopes: scopes
      Permissions.register "pages.publish", label: "Publish pages", area: "Pages", subject: Page, action: :publish, scopes: scopes
      Permissions.register "pages.move", label: "Move pages", area: "Pages", subject: Page, action: :move, scopes: scopes
      Permissions.register "pages.delete", label: "Delete pages", area: "Pages", subject: Page, action: :delete, scopes: scopes
    end

    # Tags and media assets have no single subject class of their own here
    # (a tag applies across posts, a media asset across any rich-text
    # document), so, like the administration permissions below, they carry
    # no `subject` and no scopes.
    def self.register_content
      Permissions.register "tags.manage", label: "Manage tags", area: "Content", action: :manage
      Permissions.register "media.upload", label: "Upload media", area: "Content", action: :upload
    end

    def self.register_administration
      Permissions.register "settings.manage", label: "Manage settings", area: "Administration", action: :manage
      Permissions.register "languages.manage", label: "Manage languages", area: "Administration", action: :manage
      Permissions.register "users.manage", label: "Manage users", area: "Administration", action: :manage
      Permissions.register "groups.manage", label: "Manage groups", area: "Administration", action: :manage
      Permissions.register "tokens.manage", label: "Manage tokens", area: "Administration", action: :manage
      Permissions.register "system_status.view", label: "View system status", area: "Administration", action: :view
      Permissions.register "audit.view", label: "View audit log", area: "Administration", action: :view
    end
  end
end
