# A group holds ONE grant per permission (technical cleanup spec §4.1). Grants
# of one group combine with OR, so two grants of one permission are just a
# longer way to write one wider grant -- but the group editor draws one row per
# permission and `Groups::Save`'s comparisons match grants by permission, so a
# second grant was something neither could show or reason about. The unique
# index is the guarantee; `Groups::Save` refuses a request that lists a
# permission twice before it gets that far.
#
# Existing duplicates are merged into the lowest-id row of each (group,
# permission), pairwise when there are three or more. The merge must keep what
# the pair granted: it may say "a little more" (and then says so in the output),
# never "less".
#
#   - either grant unscoped                  -> unscoped (it already covered everything);
#   - one scope covers the other (every key it sets is set in the other, with a
#     list that contains the other's and `own` only where the other has it)
#                                            -> the covering one, exactly the OR;
#   - both scoped on the same keys           -> the union of each list, `own` kept.
#     Exactly the OR while at most one list differs; with two or more differing
#     lists (content types AND pages) the union of each also admits the crossed
#     combinations, so it is reported;
#   - scoped on different keys (by content type in one, by `own` in the other)
#                                            -> no single scope expresses the OR, so
#                                               the wider reading is kept: unscoped,
#                                               reported by group and permission.
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
    return {} if one.empty? || other.empty?
    return one if covers?(one, other)
    return other if covers?(other, one)

    if one.keys.sort != other.keys.sort
      say "Group #{group_name.inspect}, #{permission}: grants scoped by different keys, widened to unscoped"
      return {}
    end

    differing = LIST_KEYS.count { |key| one.key?(key) && one[key] != other[key] }
    if differing > 1
      say "Group #{group_name.inspect}, #{permission}: grants differ in more than one list, merged as the union of each list (admits more combinations than the pair did)"
    end
    normalize(one.merge(other) { |key, a, b| LIST_KEYS.include?(key) ? a | b : a })
  end

  # `wide` grants everything `narrow` does: every restriction it sets, `narrow`
  # sets too and at least as tightly.
  def covers?(wide, narrow)
    wide.all? do |key, value|
      next false unless narrow.key?(key)

      LIST_KEYS.include?(key) ? (narrow[key] - value).empty? : true
    end
  end

  def normalize(scope)
    scope.each_with_object({}) do |(key, value), result|
      case key
      when "content_types" then result[key] = Array(value).map(&:to_s).uniq.sort
      when "page_ids"
        ids = Array(value).map { |id| id.to_s.match?(/\A\d+\z/) ? id.to_i : id }.uniq
        result[key] = ids.all?(Integer) ? ids.sort : ids
      when "own" then result[key] = true if value == true || value.to_s == "true"
      else result[key] = value
      end
    end
  end
end
