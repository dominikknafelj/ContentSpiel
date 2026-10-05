# A group holds ONE grant per permission (technical cleanup spec §4.1). Grants
# of one group combine with OR, so two grants of one permission are just a
# longer way to write one wider grant -- but the group editor draws one row per
# permission and `Groups::Save`'s comparisons match grants by permission, so a
# second grant was something neither could show or reason about. The unique
# index is the guarantee; `Groups::Save` refuses a request that lists a
# permission twice before it gets that far.
#
# Existing duplicates are merged into the lowest-id row of each (group,
# permission), pairwise when there are three or more. The merge may say "a
# little more" than the pair did (and then says so in the output), never "less".
# One rule:
#
#   - a scope with an empty list matches nothing (a dead grant), so the other
#     scope wins outright;
#   - otherwise keep only the keys BOTH scopes set: the lists of a kept list key
#     are united, `own` is kept only when both have it, any other key only when
#     both hold the same value.
#
# That yields unscoped for an unscoped partner and for scopes on different keys
# (by content type in one, by `own` in the other), the covering scope when one
# covers the other, and the union of the lists for the same keys. The result is
# the exact OR (the least scope that contains both) when one scope covers the
# other, or when the keys are equal and at most one list differs. In every
# other case it admits more than the pair did, and the migration prints both
# original scopes and the result with the group and permission: that line is the
# only record of the widening, which `down` does not undo. The fold is
# order-independent: key intersection and list union are associative and
# commutative, and a dead scope is the identity.
#
# Plain Ruby over the raw rows, deliberately no application model or registry:
# a content type that is no longer registered stays in its list untouched (a
# dead name is dormant, not meaningless -- `AccessControl::LiveGrants`), and the
# migration stays valid as the code moves on. `normalize` repeats
# `LiveGrants.normalize_scope`'s storage rule (sorted unique lists, `own` only
# when true) for the same reason.
#
# `down` restores the non-unique index only; the merge is not undone.
class OneGrantPerPermission < ActiveRecord::Migration[8.1]
  INDEX = "index_access_control_grants_on_group_id_and_permission"
  LIST_KEYS = %w[content_types page_ids].freeze

  def up
    duplicates = select_rows(<<~SQL.squish)
      SELECT group_id, permission FROM access_control_grants
      GROUP BY group_id, permission HAVING COUNT(*) > 1 ORDER BY group_id, permission
    SQL

    duplicates.each do |group_id, permission|
      rows = select_rows(<<~SQL.squish)
        SELECT id, scope FROM access_control_grants
        WHERE group_id = #{Integer(group_id)} AND permission = #{quote(permission)} ORDER BY id
      SQL
      keeper, *surplus = rows.map { |id, scope| [ id, normalize(JSON.parse(scope)) ] }
      group_name = select_value("SELECT name FROM access_control_groups WHERE id = #{Integer(group_id)}")

      merged = surplus.reduce(keeper.last) { |memo, (_, scope)| merge(memo, scope, group_name, permission) }

      execute "UPDATE access_control_grants SET scope = #{quote(merged.to_json)}::jsonb, updated_at = now() WHERE id = #{Integer(keeper.first)}"
      execute "DELETE FROM access_control_grants WHERE id IN (#{surplus.map { |id, _| Integer(id) }.join(", ")})"
    end

    remove_index :access_control_grants, name: INDEX
    add_index :access_control_grants, %i[group_id permission], unique: true, name: INDEX
  end

  def down
    remove_index :access_control_grants, name: INDEX
    add_index :access_control_grants, %i[group_id permission], name: INDEX
  end

  private

  def merge(one, other, group_name, permission)
    return other if dead?(one)
    return one if dead?(other)

    merged = normalize(one.slice(*(one.keys & other.keys)).each_with_object({}) do |(key, value), result|
      if LIST_KEYS.include?(key) then result[key] = value | other[key]
      elsif value == other[key] then result[key] = value
      end
    end)
    unless merged == one || merged == other || (one.keys.sort == other.keys.sort && LIST_KEYS.count { |key| one[key] != other[key] } <= 1)
      say "Group #{group_name.inspect}, #{permission}: #{one.to_json} + #{other.to_json} -> #{merged.to_json} (admits more than the two grants did)"
    end
    merged
  end

  def dead?(scope) = LIST_KEYS.any? { |key| scope[key] == [] }

  def normalize(scope)
    scope.sort_by { |key, _| key }.each_with_object({}) do |(key, value), result|
      case key
      when "content_types" then result[key] = Array(value).map(&:to_s).uniq.sort
      when "page_ids"
        ids = Array(value).map { |id| id.to_s.match?(/\A\d+\z/) ? id.to_i : id }.uniq
        result[key] = ids.all?(Integer) ? ids.sort : ids
      when "own" then result[key] = true if ActiveModel::Type::Boolean.new.cast(value)
      else result[key] = value
      end
    end
  end
end
