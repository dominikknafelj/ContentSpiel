module AccessControl
  # `AccessControl.scope` (design spec §3.3 "Scopes for reading"): narrows
  # a `Post`, `Page` or `ContentBlock` relation to the records the actor
  # may act on under `key` -- as one SQL condition, an OR of the actor's
  # matching grants, so a list, a search or an MCP `get_post` never loads
  # a record it would then have to throw away (or, worse, forget to).
  #
  # The contract, pinned by test/models/access_control/scoping_test.rb:
  # for every persisted record, "is it in `scope(actor, key, Model.all)`"
  # and `allowed?(actor, key, record)` give the same answer. Both are
  # decided by the same `Condition` object per grant -- `#matches?` for one
  # loaded record (the checker), `#narrow` for SQL (here) -- so the two
  # sets of rules can't drift apart: a new scope key is added in one
  # place, in both forms, next to each other.
  #
  # Which grants take part, and how they combine, is also shared with the
  # checker rather than re-derived: the actor's memoised grants
  # (`ActorGrants`), the candidate keys (a read key also looks at the
  # subject's write keys -- `Checker.candidate_keys`), OR across grants,
  # AND across the keys of one grant's scope, and for a token AND between
  # its group's grants and its user's.
  class Scoping
    # One grant's scope as a predicate on a record of the checked
    # permission's subject. Fail-closed, like the checker always was
    # (Review Focus 3): a scope key this subject can't be matched on, an
    # unknown key, an empty list, a stale page id or an unregistered
    # content type all match nothing, and never raise.
    class Condition
      def initialize(grant, user_id, permission)
        @grant = grant
        @user_id = user_id
        @permission = permission
      end

      # `branch_ids` is a callable returning the ids a `page_ids` scope is
      # matched against (the page and its ancestors -- or, for
      # `pages.create`, its future parent's; see `Checker#branch_ids`).
      # It's only called when a `page_ids` key is actually present, so a
      # post check never touches the closure table.
      def matches?(record, branch_ids)
        @grant.scope.all? do |scope_key, value|
          case scope_key
          when "content_types" then record.is_a?(Post) && Array(value).include?(record.content_type)
          when "page_ids" then record.is_a?(Page) && Array(value).map(&:to_i).intersect?(branch_ids.call)
          when "own" then !@grant.scope_own? || own?(record)
          else false
          end
        end
      end

      # The same predicate, as `base` (a relation on the subject's model,
      # without the caller's own conditions) narrowed by one `where` per
      # scope key. An empty scope leaves `base` alone -- which `.or`
      # reads as TRUE, exactly the "no restriction" `matches?` returns for
      # it. A key that can't match is `where(id: [])`, which Rails renders
      # as `1=0`. Every value goes in as a bind parameter.
      #
      # The mirror image of each `matches?` branch:
      # - `content_types` -> `content_type IN (...)`;
      # - `page_ids` -> the page (for `pages.create`: its parent, which is
      #   what the checker's `branch_ids` uses) is a descendant-or-self of
      #   a listed root, via the closure table. A root page has no parent,
      #   and `NULL IN (...)` is never true, matching the checker's "a new
      #   root is in no branch";
      # - `own: true` -> `author_id = <user>`. The checker's other `own`
      #   case, "an unsaved post is always the actor's own", has nothing
      #   to mirror: a relation only ever holds persisted rows.
      def narrow(base)
        @grant.scope.reduce(base) do |relation, (scope_key, value)|
          case scope_key
          when "content_types"
            return nothing(base) unless base.model == Post
            relation.where(content_type: Array(value))
          when "page_ids"
            return nothing(base) unless base.model == Page
            column = @permission.key == "pages.create" ? :parent_id : :id
            relation.where(column => PageHierarchy.where(ancestor_id: Array(value).map(&:to_i)).select(:descendant_id))
          when "own"
            next relation unless @grant.scope_own?
            return nothing(base) unless base.model == Post && @user_id.present?
            relation.where(author_id: @user_id)
          else
            return nothing(base)
          end
        end
      end

      private

      # Design spec §3.3: "There is no record yet, so `own` always matches
      # on create" -- the post's author becomes the actor.
      def own?(record)
        return false unless record.is_a?(Post)

        record.new_record? || (@user_id.present? && record.author_id == @user_id)
      end

      def nothing(base) = base.where(id: [])
    end

    def initialize(actor, key, channel)
      @actor = actor
      @permission = Permissions.fetch(key)
      @channel = channel
    end

    # Owners and trusted code paths get `relation` back untouched (bar the
    # block edge case in `#all_blocks`); an actor that can't hold grants
    # (a nil actor on `:admin`/`:mcp`, a revoked or group-less token) gets
    # `relation.none`. Otherwise the
    # grant conditions are ANDed onto `relation` with `Relation#and`, not
    # `#merge`: `merge` lets a later equality on a column *replace* an
    # earlier one, so `Post.where(content_type: "blog")` merged with a
    # grant's `content_type IN ('blog', 'now_update')` would silently widen
    # the caller's own filter. `and` only ever adds predicates. The
    # conditions are built on `relation.unscope(:where)` so they share the
    # caller's order/limit/joins, which `and` requires.
    def apply(relation)
      model = relation.model
      check_subject!(model)
      unrestricted = Checker.trusted?(@actor, @channel) || owner?
      return relation.none unless unrestricted || actor_may_hold_grants?

      if model <= ContentBlock
        unrestricted ? all_blocks(relation) : narrow(relation, blocks(relation.unscope(:where)))
      else
        unrestricted ? relation : narrow(relation, filter(relation.unscope(:where), @permission))
      end
    end

    private

    def narrow(relation, conditions) = conditions ? relation.and(conditions) : relation.none

    # An owner or trusted code path sees every block -- except those whose
    # owner's subject lacks the key's action (`pages.move` on a post-owned
    # block), where `allowed?` raises rather than allows; see `#blocks`.
    def all_blocks(relation)
      unsupported = owner_permissions.reject { |_owner_type, permission| permission }.keys
      unsupported.empty? ? relation : relation.where.not(owner_type: unsupported)
    end

    # `{"Page" => pages.<action>, "Post" => posts.<action>}`, nil for a
    # combination that isn't registered.
    def owner_permissions
      Checker::BLOCK_OWNER_PREFIX.to_h do |owner_type, prefix|
        [ owner_type, Permissions.find("#{prefix}.#{@permission.action}") ]
      end
    end

    def actor_may_hold_grants?
      case @actor
      when User then true
      when ApiToken then @actor.revoked_at.nil? && @actor.user.present? && @actor.group_id.present?
      else false
      end
    end

    # An owner's *token* is still limited by its group (see `#filter`), so
    # only a user who is an owner skips filtering.
    def owner? = @actor.is_a?(User) && @actor.owner?

    # The OR of `permission`'s matching grants as a relation from `base`,
    # or nil when no grant can match (the caller turns that into
    # `.none`). For a token: its group's grants AND its user's, with `own`
    # on either side meaning the token's user -- `Checker#token_allowed?`'s
    # intersection, as SQL.
    def filter(base, permission)
      keys = Checker.candidate_keys(permission)
      grants = ActorGrants.for(@actor)

      case @actor
      when User
        any_of(base, grants.user_grants.for(keys), @actor.id, permission)
      when ApiToken
        token_side = any_of(base, grants.token_grants.for(keys), @actor.user_id, permission)
        return token_side if token_side.nil? || @actor.user.owner?

        user_side = any_of(base, grants.user_grants.for(keys), @actor.user_id, permission)
        user_side && token_side.and(user_side)
      end
    end

    def any_of(base, grants, user_id, permission)
      grants.map { |grant| Condition.new(grant, user_id, permission).narrow(base) }.reduce(:or)
    end

    # Blocks follow their owner (design spec §3.1, `Checker#resolve_block`):
    # the key's action on a page-owned block is `pages.<action>` on its
    # page, on a post-owned block `posts.<action>` on its post, whichever
    # subject the key itself names. So the block scope is "owned by a page
    # in the page scope, or by a post in the post scope", each side a
    # subquery built by `#filter` against its own model.
    #
    # An action one owner's subject lacks (`pages.move` -> there's no
    # `posts.move`) makes `allowed?` raise for such a block -- a
    # programmer error on a single record. A relation can't raise per row,
    # so that side simply matches nothing. Blocks with any other owner
    # type (none exist yet) match nothing either.
    def blocks(base)
      sides = owner_permissions.filter_map do |owner_type, owner_permission|
        next unless owner_permission

        owner_model = owner_type.constantize
        owners = filter(owner_model.unscoped, owner_permission) or next
        base.where(owner_type: owner_type, owner_id: owners.select(:id))
      end
      sides.reduce(:or)
    end

    # Like `Checker#check_subject!`, a mismatch is a programmer error: the
    # key must govern the relation's model -- for blocks, a page or post
    # key (either one: blocks follow their owner). Admin-area keys have no
    # records to filter.
    def check_subject!(model)
      subject = @permission.subject
      valid =
        if model <= ContentBlock then [ Page, Post ].include?(subject)
        else subject.present? && model <= subject
        end
      return if valid

      raise ArgumentError, "#{@permission.key} can't scope a #{model} relation"
    end
  end
end
