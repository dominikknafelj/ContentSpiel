require "test_helper"

# `Media::Destroy` (media library design spec §5.1): deletes an unused
# library image. Refused while any `media_usages` row names it, and backed
# by the `on_delete: :restrict` FKs when the index is behind (Review Focus 4).
class Media::DestroyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def upload_by(user)
    file = Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png")
    result = Media::Upload.call(file: file, actor: user)
    assert result.ok?, result.errors.inspect
    result.record
  end

  def hero_page(title, asset)
    as_owner do
      page = create_page(title: title)
      assert Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id }).ok?
      page
    end
  end

  test "deletes an unused asset, records media.deleted and purges the file after commit" do
    asset = upload_by(users(:author))
    blob = asset.file.blob

    result = nil
    assert_difference "Media::Asset.count", -1 do
      result = as(users(:two)) { Media::Destroy.call(asset) }
    end

    assert result.ok?, result.errors.inspect
    event = Audit::Event.find_by!(action: "media.deleted")
    assert_equal "tiny", event.subject_label
    assert_equal "tiny.png", event.snapshot["filename"]
    assert_enqueued_with(job: ActiveStorage::PurgeJob, args: [ blob ])
  end

  test "the uploader deletes their own upload without media.manage" do
    asset = upload_by(users(:author))

    assert as(users(:author)) { Media::Destroy.call(asset) }.ok?
    assert_not Media::Asset.exists?(asset.id)
  end

  test "someone else without media.manage is denied" do
    asset = upload_by(users(:one))

    result = as(users(:author)) { Media::Destroy.call(asset) }

    assert result.denied?
    assert_equal [ "You don't have permission to manage media" ], result.errors
    assert Media::Asset.exists?(asset.id)
    assert_not Audit::Event.exists?(action: "media.deleted")
  end

  test "a used asset is refused, naming the page" do
    asset = upload_by(users(:author))
    hero_page("About us", asset)

    result = nil
    assert_no_difference "Media::Asset.count" do
      result = as(users(:two)) { Media::Destroy.call(asset) }
    end

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "This image is used on the page “About us”" ], result.errors
    assert_not Audit::Event.exists?(action: "media.deleted")
    assert_no_enqueued_jobs(only: ActiveStorage::PurgeJob)
  end

  test "the message lists three usages and counts the rest, blocks named by their page or post" do
    asset = upload_by(users(:author))
    %w[One Two Three].each { |title| hero_page(title, asset) }
    as_owner do
      page = create_page(title: "Four")
      assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "image", media_asset_id: asset.id }).ok?
      post = create_post(title: "Five")
      assert Posts::Save.call(post, translations: { "en" => { body: rich_doc("::image{asset=\"#{asset.id}\"}") } }).ok?
    end

    result = as(users(:two)) { Media::Destroy.call(asset) }

    assert_match(/\AThis image is used on the page “One”, the page “Two”, the page “Three” and 2 more\z/, result.errors.first)
  end

  test "a place the actor can't read is named neutrally" do
    asset = upload_by(users(:author))
    hero_page("Secret", asset)
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "media.manage", scope: {})

    result = as(users(:editor_branch)) { Media::Destroy.call(asset) }

    assert_equal [ "This image is used on a page you can't open" ], result.errors
  end

  # Review Focus 4: the usage index is behind (a race, a raw write) -- the
  # service's own check passes, the FK still restricts, and the database
  # error becomes a failure rather than a 500.
  test "an unindexed reference is caught by the foreign key and fails cleanly" do
    asset = upload_by(users(:author))
    page = as_owner { create_page(title: "Raced") }
    page.update_column(:hero_media_asset_id, asset.id)
    assert_not asset.used?

    result = as(users(:two)) { Media::Destroy.call(asset) }

    assert_not result.ok?
    assert_equal [ "This image is still in use and can't be deleted" ], result.errors
    assert Media::Asset.exists?(asset.id)
    assert asset.reload.file.attached?
    assert_not Audit::Event.exists?(action: "media.deleted")
    assert_no_enqueued_jobs(only: ActiveStorage::PurgeJob)
  end
end
