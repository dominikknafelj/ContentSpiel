module AccessControl
  # A group's stored grants as they stand today (design spec §3.1/§3.3,
  # Review Focus 3): what the group editor shows, and what `Groups::Save`
  # compares a submitted grant list against to tell "new or changed"
  # from "unchanged".
  #
  # A grant goes stale when the world it points at changes under it -- its
  # branch root page is deleted, its content type is no longer registered,
  # or its permission key itself is gone (a removed plugin). None of that is
  # an error: the stale value simply matches nothing (`Scoping::Condition`,
  # which reads a grant's content types through the same registry reader as
  # this class, `Permissions.content_type_choices` -- so a name filed under
  # `gone_types` here grants nothing there, even on posts that still carry
  # that type, until a type of that name is registered again).
  # Here each grant is split into the part that still means something and
  # the part that doesn't:
  #
  # - `entries`: the grants that still match something, with their stale
  #   values taken out (`removed` names them, for the editor's "no longer
  #   exists" note). Dropping a deleted page id from `[deleted, kept]`
  #   changes nothing about what the grant matches.
  # - `dead`: the grants that match nothing at all any more -- an
  #   unregistered permission, or a scope list whose *every* value is stale.
  #   These must not come back as an entry: an empty `content_types` or
  #   `page_ids` list means "matches nothing", but the editor can only say
  #   "none ticked", which it submits as "no restriction" -- so showing a
  #   dead grant as ticked would silently turn it into an unscoped one on
  #   the next save. The editor shows them unticked, with a note, and they
  #   disappear when the group is saved.
  #
  # Scopes come out normalized (`.normalize_scope`) so two spellings of
  # the same scope compare equal.
  class LiveGrants
    # `gone_types`: the content types taken out of `scope` because they are no
    # longer registered, by name. The editor shows each as a warn chip and
    # CARRIES it (`#carried_attributes`) until its Remove is pressed, so a form
    # saved as rendered changes nothing (`Groups::Save#live`).
    Entry = Data.define(:permission, :scope, :removed, :gone_types) do
      def attributes = { permission: permission, scope: scope }

      # `attributes`, with the removed content types put back: what the editor
      # renders (and so submits) for this grant.
      def carried_attributes
        return attributes if gone_types.empty?

        { permission: permission, scope: scope.merge("content_types" => (scope.fetch("content_types", []) + gone_types).sort) }
      end

      # The removed values that are not content types, as notes.
      def removed_notes = removed.grep_v(/\Acontent type /)
    end
    Dead = Data.define(:permission, :removed)

    # A scope as the grant stores it: string keys; `content_types` sorted,
    # unique strings; `page_ids` sorted, unique integers (a value that isn't
    # one is kept as given, for `Grant`'s validation to reject); `own` only
    # when true -- `own: false` restricts nothing, so it's the same as no
    # key. Any other key is kept for validation to reject.
    def self.normalize_scope(scope)
      scope.to_h.stringify_keys.each_with_object({}) do |(key, value), result|
        case key
        when "content_types" then result[key] = Array(value).map(&:to_s).uniq.sort
        when "page_ids"
          ids = Array(value).map { |id| integer_or_self(id) }.uniq
          result[key] = ids.all?(Integer) ? ids.sort : ids
        when "own" then result[key] = true if ActiveModel::Type::Boolean.new.cast(value)
        else result[key] = value
        end
      end
    end

    def self.integer_or_self(value)
      return value if value.is_a?(Integer)

      Integer(value.to_s, 10, exception: false) || value
    end

    attr_reader :entries, :dead

    # One query at most, for the referenced page ids that still exist.
    def initialize(grants)
      page_ids = grants.flat_map(&:scope_page_ids).uniq
      @existing_page_ids = page_ids.empty? ? Set.new : Page.where(id: page_ids).pluck(:id).to_set
      @content_types = Permissions.content_type_choices.to_set
      @entries = []
      @dead = []
      grants.each { |grant| classify(grant) }
    end

    def attributes = entries.map(&:attributes)

    # What the group editor renders: the live scope plus any removed content
    # types, carried (see `Entry#carried_attributes`).
    def carried_attributes = entries.map(&:carried_attributes)

    def entry_for(key) = entries.find { |entry| entry.permission == key }
    def dead_for(key) = dead.select { |grant| grant.permission == key }

    private

    def classify(grant)
      return @dead << Dead.new(permission: grant.permission, removed: [ "the permission itself" ]) if grant.permission_definition.nil?

      scope = self.class.normalize_scope(grant.scope)
      removed = []
      gone_types = []
      alive = true

      if scope.key?("content_types")
        gone = scope["content_types"].reject { |name| @content_types.include?(name) }
        removed += gone.map { |name| "content type “#{name}” (no longer exists)" }
        gone_types = gone
        scope["content_types"] -= gone
        alive &&= scope["content_types"].any?
      end

      if scope.key?("page_ids")
        gone = scope["page_ids"].reject { |id| @existing_page_ids.include?(id) }
        removed += gone.map { "a page that no longer exists" }
        scope["page_ids"] -= gone
        alive &&= scope["page_ids"].any?
      end

      alive &&= (scope.keys - %w[content_types page_ids own]).empty?

      if alive
        @entries << Entry.new(permission: grant.permission, scope: scope, removed: removed, gone_types: gone_types)
      else
        @dead << Dead.new(permission: grant.permission, removed: removed)
      end
    end
  end
end
