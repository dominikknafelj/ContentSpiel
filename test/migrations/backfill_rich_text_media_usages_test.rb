require "test_helper"
require Rails.root.join("db/migrate/20260929070000_backfill_rich_text_media_usages").to_s

# Media library final fix wave (C1): a database that ran
# `MoveImagesIntoMediaLibrary` before it indexed rich text holds bodies that
# embed library images with no `rich_text` usage row -- those images read as
# "Unused" and can be deleted. The follow-up migration adds the rows.
class BackfillRichTextMediaUsagesMigrationTest < ActiveSupport::TestCase
  def migrate(direction) = ActiveRecord::Migration.suppress_messages { BackfillRichTextMediaUsages.new.migrate(direction) }

  def rich_text_rows = Media::Usage.where(role: "rich_text").pluck(:media_asset_id, :owner_type, :owner_id, :locale).sort_by { |row| [ row[1], row[3] ] }

  setup do
    @asset = create_media_asset
    @post = create_post(title: "Embeds it")
    @post.assign_body(rich_doc(%(- ::image{asset="#{@asset.id}"})), locale: "de")
    @post.save!
    @block = root_page.content_blocks.create!(block_type: :rich_text, position: 0)
    @block.assign_body(rich_doc(%(> ::image{asset="#{@asset.id}"})), locale: "en")
    @block.save!
    Media::Usage.delete_all
  end

  test "an embedded image is no longer unused, and the rows match what UsageIndex computes" do
    assert_includes Media::Asset.unused, @asset

    migrate(:up)

    assert_not_includes Media::Asset.unused, @asset
    expected = [ [ @asset.id, "ContentBlock", @block.id, "en" ], [ @asset.id, "Post", @post.id, "de" ] ]
    assert_equal expected, rich_text_rows

    Media::UsageIndex.rebuild_all
    assert_equal expected, rich_text_rows
  end

  test "it is idempotent and keeps rows the index already holds" do
    Media::UsageIndex.refresh(@post)

    assert_difference -> { Media::Usage.count }, 1 do
      migrate(:up)
    end
    assert_no_difference -> { Media::Usage.count } do
      migrate(:up)
    end
  end
end
