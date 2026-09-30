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
      register_trash
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
    #
    # The media library (media library design spec §5.1) has two:
    # `media.upload` -- upload, browse the library and choose an image for
    # a hero, an image block or a rich-text image -- and `media.manage` --
    # edit any image's title/alt/caption and delete any image. The uploader
    # of an image may edit or delete that one image without `media.manage`
    # (`Media::Save`/`Media::Destroy`'s own "ownership" rule); the library
    # itself isn't read-scoped, so there's no `own` scope here to express
    # that with -- ownership is decided in those two services instead.
    def self.register_content
      Permissions.register "tags.manage", label: "Manage tags", area: "Content", action: :manage
      Permissions.register "media.upload", label: "Upload media", area: "Content", action: :upload
      Permissions.register "media.manage", label: "Manage media", area: "Content", action: :manage
    end

    def self.register_administration
      Permissions.register "settings.manage", label: "Manage settings", area: "Administration", action: :manage
      Permissions.register "languages.manage", label: "Manage languages", area: "Administration", action: :manage
      Permissions.register "users.manage", label: "Manage users", area: "Administration", action: :manage
      Permissions.register "groups.manage", label: "Manage groups", area: "Administration", action: :manage
      Permissions.register "tokens.manage", label: "Manage tokens", area: "Administration", action: :manage
      Permissions.register "system_status.view", label: "View system status", area: "Administration", action: :view
      # Not content-scoped (final fix wave, Minor 3): the log holds
      # snapshots of every record, whatever the viewer may read elsewhere,
      # and the label says so wherever it's offered or denied.
      Permissions.register "audit.view", label: "View audit log (all content)", area: "Administration", action: :view
    end

    # Its own area, not folded into Administration (global constraints:
    # Admin only, and the one permission that both empties the whole trash
    # and, per `trash.empty` ruling in the plan's spec corrections, purges
    # any single trashed item too) -- unscoped, like the Administration
    # permissions above, since holding it is all-or-nothing.
    def self.register_trash
      Permissions.register "trash.empty", label: "Empty trash", area: "Trash", action: :empty
    end
  end
end
