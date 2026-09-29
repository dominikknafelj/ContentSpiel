require "test_helper"

# `Media::Save` (media library design spec §5.1): edits a library image's
# title and translated alt/caption defaults. Needs `media.manage`, or
# ownership of the upload (plus `media.upload`, see the service's comment).
class Media::SaveTest < ActiveSupport::TestCase
  def upload_by(user)
    file = Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png")
    result = Media::Upload.call(file: file, actor: user)
    assert result.ok?, result.errors.inspect
    result.record
  end

  test "the uploader edits their own upload without media.manage" do
    asset = upload_by(users(:author))

    result = as(users(:author)) do
      Media::Save.call(asset, attributes: { title: "Studio" }, translations: { "en" => { alt: "The studio" }, "de" => { alt: "Das Studio" } })
    end

    assert result.ok?, result.errors.inspect
    asset.reload
    assert_equal "Studio", asset.title
    assert_equal "The studio", asset.alt(locale: :en)
    assert_equal "Das Studio", asset.alt(locale: :de)
  end

  test "someone else without media.manage is denied and nothing changes" do
    asset = upload_by(users(:one))

    result = as(users(:author)) { Media::Save.call(asset, attributes: { title: "Hijacked" }) }

    assert result.denied?
    assert_equal [ "You don't have permission to manage media" ], result.errors
    assert_equal "tiny", asset.reload.title
    event = Audit::Event.find_by!(action: "access.denied")
    assert_equal({ "permission" => "media.manage" }, event.metadata)
    assert_equal asset, event.subject
  end

  test "media.manage edits anyone's upload and records media.updated with the changes" do
    asset = upload_by(users(:author))

    result = as(users(:two)) do
      Media::Save.call(asset, attributes: { title: "Renamed" }, translations: { "en" => { caption: "A caption" } })
    end

    assert result.ok?, result.errors.inspect
    event = Audit::Event.find_by!(action: "media.updated")
    assert_equal asset, event.subject
    assert_equal users(:two), event.actor
    assert_equal [ "tiny", "Renamed" ], event.field_changes["title"]
    assert_equal [ nil, "A caption" ], event.field_changes["en caption"]
    assert_equal "Renamed", event.snapshot["title"]
    assert_equal({ "en" => "A caption" }, event.snapshot["caption"])
    assert_equal "tiny.png", event.snapshot["filename"]
  end

  test "only the title is taken from attributes" do
    asset = upload_by(users(:author))

    as(users(:two)) { Media::Save.call(asset, attributes: { title: "T", created_by_id: users(:two).id, byte_size: 1 }) }

    asset.reload
    assert_equal users(:author), asset.created_by
    assert_not_equal 1, asset.byte_size
  end

  test "a save that changes nothing records nothing" do
    asset = upload_by(users(:author))

    assert as(users(:two)) { Media::Save.call(asset, attributes: { title: "tiny" }) }.ok?
    assert_not Audit::Event.exists?(action: "media.updated")
  end

  # A token is judged on token ∩ user, as everywhere: the uploader's own
  # token still needs its group to hold `media.upload` (fail closed -- a
  # Read-only token can't edit anything, even its user's own uploads).
  test "an uploader's token needs media.upload in its group" do
    asset = upload_by(users(:author))
    read_only, = ApiToken.generate!(users(:author), group: access_control_groups(:read_only))
    author, = ApiToken.generate!(users(:author), group: access_control_groups(:author))

    assert as(read_only, channel: :mcp) { Media::Save.call(asset, attributes: { title: "Nope" }) }.denied?
    assert as(author, channel: :mcp) { Media::Save.call(asset, attributes: { title: "Yes" }) }.ok?
    assert_equal "Yes", asset.reload.title
  end
end
