# Media library Task 3: the usage index (design spec §3.2/§3.3). `media_usages`
# is a derived table -- nobody writes to it directly, `Media::UsageIndex`
# rebuilds one owner's rows wholesale from that owner's own current state
# (a page's hero, a block's image, a rich-text body's `image` nodes). It
# exists so "where is this image used", the "Unused" filter, and the delete
# guard (`Media::Destroy`) are all a plain index lookup rather than a scan
# of every page/post/block on every request.
#
# `owner_type`/`owner_id` is `Page`, `ContentBlock` or `Post` (never `Media
# ::Asset` itself). `role` is `hero`, `block_image` or `rich_text`; `locale`
# is only meaningful for `rich_text` (one document per locale can each
# reference the same or a different asset) and stays nil for `hero`/
# `block_image`, which aren't per-locale at all -- a page has one hero, a
# block has one image, full stop.
#
# The FK on `media_asset_id` is the actual backstop (created `on_delete:
# :restrict` here, switched to NO ACTION by `MediaForeignKeysNoAction` so
# Postgres 18 still raises `InvalidForeignKey`): even if
# `Media::Destroy`'s own usage check (a later task) were ever bypassed --
# a race, a forged request, a bug -- Postgres itself refuses to delete an
# asset a usage row still points at, turning what would otherwise be a
# silently dangling reference into an ordinary `ActiveRecord
# ::InvalidForeignKey` the caller has to handle (global constraints, Review
# Focus 4).
#
# **Ruling (plan preflight, T3->T4):** this migration also adds
# `pages.hero_media_asset_id` and `content_blocks.media_asset_id` -- the two
# direct references Task 4 would otherwise introduce -- so the index this
# task builds has something real to read and test against now, instead of
# waiting on Task 4's data migration. Task 4 only migrates the *existing*
# `hero_image`/`image` attachments onto these already-existing columns and
# drops the old attachment rows; it must not re-add either column.
class CreateMediaUsages < ActiveRecord::Migration[8.1]
  def change
    create_table :media_usages do |t|
      t.references :media_asset, null: false, foreign_key: { on_delete: :restrict }
      # `polymorphic: true` defaults to `index: true`, which for a
      # polymorphic reference is the composite `[owner_type, owner_id]`
      # index the global constraints call for -- no separate `add_index`
      # needed for that half.
      t.references :owner, polymorphic: true, null: false
      t.string :role, null: false
      t.string :locale

      t.timestamps
    end

    # One row per (asset, owner, role, locale) -- what `Media::UsageIndex`
    # treats as "the same usage" and never duplicates on a re-refresh.
    add_index :media_usages, [ :media_asset_id, :owner_type, :owner_id, :role, :locale ], unique: true

    add_reference :pages, :hero_media_asset, foreign_key: { to_table: :media_assets, on_delete: :restrict }, index: true
    add_reference :content_blocks, :media_asset, foreign_key: { on_delete: :restrict }, index: true
  end
end
