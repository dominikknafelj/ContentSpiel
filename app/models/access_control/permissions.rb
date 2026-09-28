# The registry of permissions (design spec §3.1) that `AccessControl
# .allowed?`/`.scope` (a later task) check grants against, and CS Studio's
# group editor lists grouped by `area`. Built-ins register here from
# `config/initializers/types.rb`'s `to_prepare` block, after a `reset!`;
# plugins will call the same `.register`, under a prefixed `owner/name` key.
#
# Mirrors `ContentModel::Registry` in spirit -- register/fetch-by-key/
# reset!, a duplicate raises, a malformed key is rejected -- but doesn't
# `extend` it: that mixin's `register` takes a DSL block and calls
# `definition.finalize!`, built for types that accumulate a nested field
# schema over several calls. A permission has no such schema -- every field
# arrives as a keyword argument in one call -- so a plain method fits
# better than bending a five-argument value to share a block-based mixin.
# (`RichText::Schema` made the same call, for its own reasons -- see that
# file's comment.)
module AccessControl
  module Permissions
    # A permission key is `key.action` (e.g. `posts.edit`), or
    # `owner/key.action` for a plugin's own permission (design spec §3.1) --
    # one optional `owner/` prefix, one mandatory `.action` suffix,
    # lowercase_words on every segment. Mirrors `ContentModel::Registry
    # ::NAME_FORMAT`'s owner-prefix shape, plus the `.action` suffix a
    # permission key always has and a type name never does.
    KEY_FORMAT = /\A([a-z][a-z0-9_]*\/)?[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\z/

    # The only scope kinds a grant can narrow a permission by (design spec
    # §3.1/§3.2): `content_type` and `own` (posts), `branch` (pages, via
    # `page_hierarchies`). `.register` rejects any other symbol up front,
    # so a typo'd scope fails at boot (or in a plugin's own test) instead
    # of silently never matching any grant later.
    ALLOWED_SCOPES = %i[content_type branch own].freeze

    class << self
      # `register(key, label:, area:, action:, subject: nil, scopes: [])`
      # -- every field a keyword argument, no DSL block (see the module
      # comment). `subject` is stored as the actual class constant
      # (`Post`, `Page`, `ContentBlock`, or `nil`), not its name -- unlike a
      # type registry's string name, there's no risk of that constant going
      # stale across a development reload: this registry is reset and every
      # built-in re-registered together, inside the same `to_prepare` block
      # that reloads `Post`/`Page`/`ContentBlock` themselves
      # (config/initializers/types.rb), so the constant a freshly-run
      # `register` call resolves is always the just-reloaded class, never
      # one left over from before the reload.
      def register(key, label:, area:, action:, subject: nil, scopes: [])
        key = key.to_s
        unless key.match?(KEY_FORMAT)
          raise ArgumentError, "#{key.inspect} isn't a valid permission key (expected key.action or owner/key.action)"
        end
        raise DuplicatePermission, "#{key.inspect} is already a registered permission" if registry.key?(key)

        scopes = Array(scopes).map(&:to_sym)
        unknown_scopes = scopes - ALLOWED_SCOPES
        if unknown_scopes.any?
          raise ArgumentError, "#{unknown_scopes.map(&:inspect).join(", ")} isn't an allowed scope (expected #{ALLOWED_SCOPES.join(", ")})"
        end

        registry[key] = Permission.new(key: key, label: label, area: area, subject: subject, action: action.to_sym, scopes: scopes)
      end

      def fetch(key) = registry.fetch(key.to_s) { raise UnknownPermission, "#{key.inspect} isn't a registered permission" }
      def find(key) = registry[key.to_s]
      def all = registry.values
      def keys = registry.keys
      def reset! = @registry = {}

      # Every permission whose `subject` is `klass` -- e.g. a record
      # editor listing only the permissions relevant to what it's showing.
      def for_subject(klass) = all.select { |permission| permission.subject == klass }

      # Read live from `ContentTypes` rather than snapshotted at
      # registration time (design spec §3.1): a plugin's content type
      # registered after a `content_type`-scoped permission is still a
      # valid scope value for it, and one later unregistered simply stops
      # being offered as a choice -- neither requires this permission to
      # re-register.
      def content_type_choices = ContentTypes.names

      private

      def registry = (@registry ||= {})
    end
  end
end
