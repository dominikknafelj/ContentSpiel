# Schema half of groups, memberships, grants, owners and post authorship
# (access-control design spec §3.2). The data half -- seeding the four
# built-in groups and backfilling existing rows -- is the next migration
# (`SeedAccessControlGroups`), kept separate so this one stays a plain,
# fully-reversible `change` (every operation below is one Rails already
# knows how to invert) and the data migration can assume the columns it
# writes into already exist.
class CreateAccessControl < ActiveRecord::Migration[8.1]
  def change
    create_table :access_control_groups do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :built_in, default: false, null: false
      t.timestamps
    end

    # Case-insensitive uniqueness (design spec §3.2) enforced at the DB
    # level, not just by the model's `uniqueness: case_sensitive: false`
    # validation -- a validation alone can't stop two concurrent creates of
    # "Admin" and "admin" from both passing it and racing to insert.
    add_index :access_control_groups, "LOWER(name)", unique: true, name: "index_access_control_groups_on_lower_name"

    create_table :access_control_memberships do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :group, null: false, foreign_key: { to_table: :access_control_groups, on_delete: :cascade }
      t.timestamps
    end
    add_index :access_control_memberships, [ :user_id, :group_id ], unique: true

    create_table :access_control_grants do |t|
      t.references :group, null: false, foreign_key: { to_table: :access_control_groups, on_delete: :cascade }
      t.string :permission, null: false
      t.jsonb :scope, default: {}, null: false
      t.timestamps
    end
    add_index :access_control_grants, [ :group_id, :permission ]

    add_column :users, :owner, :boolean, default: false, null: false

    # Nullable for now -- the very next migration backfills every existing
    # token to the built-in Admin group and then tightens this to NOT NULL
    # (design spec §3.2). Nothing but that backfill window ever inserts a
    # null one: a brand new token always gets a group explicitly, via
    # `ApiToken.generate!`'s `group:` keyword (interim default: the
    # built-in Admin group, until a later task makes the caller choose).
    add_reference :api_tokens, :group, foreign_key: { to_table: :access_control_groups }, index: true

    # Nullable forever, unlike `api_tokens.group_id` above: not every post
    # has an author, and a user delete nullifies this rather than orphaning
    # the post or blocking the delete (design spec §3.2) -- "own" then
    # simply stops matching for anyone, which is fine, not an error.
    add_reference :posts, :author, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
  end
end
