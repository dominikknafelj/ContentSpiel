module Audit
  # Folds a burst of edits into one event (access-control design spec
  # §4.2). CS Studio autosaves on every pause in typing, so without this a
  # five-minute editing session would log dozens of `post.updated` rows --
  # the log would be accurate and unreadable.
  #
  # Only two kinds of action coalesce:
  # - `*.updated`, keyed by action, actor and subject;
  # - `access.denied`, keyed by actor, subject *and* the denied permission
  #   (`metadata["permission"]`), so a forged autosave loop hammering one
  #   forbidden record is one event, but a denial of a different permission
  #   still stands out.
  # Everything else (`post.published`, `user.deleted`, ...) is a discrete
  # moment someone may need to find on its own, and never coalesces.
  module Coalescer
    module_function

    def coalescible?(action) = action.end_with?(".updated") || action == "access.denied"

    # Extends and returns the open event matching `attributes`, or nil when
    # there is none (or the action never coalesces) and a new row is
    # needed. Called inside a transaction (`Audit.record`'s own, nested in
    # the caller's when there is one): the candidate row is locked
    # (`FOR UPDATE`) so two concurrent saves can't both read the same
    # `field_changes` and have the second silently drop the first's merge.
    # Two concurrent *first* events for one subject can still both insert
    # -- that costs one extra row, never a lost change.
    def extend_existing(attributes, now:)
      action = attributes[:action]
      return unless coalescible?(action)

      candidate = candidates(attributes, now:).lock.first
      return unless candidate

      candidate.update!(
        field_changes: merge(candidate.field_changes, attributes[:field_changes]),
        # A later event with no snapshot (an `access.denied`, which never
        # has one) must not wipe the one already stored.
        snapshot: attributes[:snapshot] || candidate.snapshot,
        last_occurred_at: now,
        # How many saves the row stands for ("N saves" in the log, D22).
        occurrences: candidate.occurrences + 1
      )
      candidate
    end

    def candidates(attributes, now:)
      actor = attributes[:actor]
      subject = attributes[:subject]

      scope = Event.where(
        action: attributes[:action],
        actor_type: actor&.class&.polymorphic_name, actor_id: actor&.id,
        subject_type: subject&.class&.polymorphic_name, subject_id: subject&.id,
        last_occurred_at: (now - COALESCE_WINDOW)..
      )
      if attributes[:action] == "access.denied"
        # `metadata ->> 'permission' IS NOT DISTINCT FROM ?`: a denial recorded
        # without a permission matches only another without one, which `=`
        # (NULL = NULL is not true) would never say.
        permission = SqlNodes.json_text(Event.arel_table[:metadata], "permission")
        scope = scope.where(permission.is_not_distinct_from(attributes[:metadata]["permission"]))
      end
      scope.order(last_occurred_at: :desc, id: :desc)
    end

    # Per field: the original old value and the latest new value (spec
    # §4.2). A body summary (`{digest_before, digest_after}`) merges the
    # same way. A field that ends up back where it started is kept -- the
    # edits did happen, and the log shouldn't pretend otherwise.
    def merge(existing, incoming)
      existing.merge(incoming) do |_field, old, new|
        if old.is_a?(Array) && new.is_a?(Array)
          [ old.first, new.last ]
        elsif old.is_a?(Hash) && new.is_a?(Hash) && old.key?("digest_before")
          { "digest_before" => old["digest_before"], "digest_after" => new["digest_after"] }
        else
          new
        end
      end
    end
  end
end
