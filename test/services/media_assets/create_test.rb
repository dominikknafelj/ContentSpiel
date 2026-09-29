require "test_helper"

# `MediaAssets::Create` is a plain alias of `Media::Upload` until Task 6
# removes it (its own class comment) -- `test/services/media/upload_test.rb`
# covers the behaviour; this only pins that the old name still works.
class MediaAssets::CreateTest < ActiveSupport::TestCase
  test "delegates to Media::Upload" do
    upload = Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png")
    result = as(users(:author)) { MediaAssets::Create.call(file: upload) }

    assert_operator MediaAssets::Create, :<, Media::Upload
    assert result.ok?, result.errors.inspect
    assert Audit::Event.exists?(action: "media.uploaded", subject: result.record)
  end
end
