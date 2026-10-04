require "test_helper"

# The byte budget of a bulk answer's flash (final fix wave 2, Task 17's p4):
# sentences plus Undo URL together, in bytes, because the flash lives in the
# 4 KB session cookie and titles are multi-byte.
class Admin::BulkResponsesTest < ActiveSupport::TestCase
  FakePost = Struct.new(:id, :name) do
    def title(locale: nil) = name
  end

  class Host
    include Admin::BulkResponses
    attr_reader :flash

    def initialize = @flash = {}
    def helpers = ActionController::Base.helpers
    def admin_locale = :en
    public :flash_bulk_result
  end

  def posts(count, name) = Array.new(count) { |i| FakePost.new(i + 1, name) }

  test "an Undo that fits the budget with its sentences is kept" do
    host = Host.new
    host.flash_bulk_result(done: posts(2, "A"), verb: "Moved", failed_phrase: "moved to the trash", suffix: " to the trash", undo_url: "/undo?x=1")
    assert_equal({ "label" => "Undo", "url" => "/undo?x=1" }, host.flash[:undo])
    assert_equal "Moved 2 posts to the trash.", host.flash[:notice]
  end

  test "an Undo URL under its own limit is dropped when the sentences push the whole over the budget, counted in bytes" do
    host = Host.new
    # 3 refused titles of 60 three-byte characters: ~540 bytes of sentence,
    # 60 characters each but 180 bytes. The URL alone (1,490 bytes) is allowed.
    refused = posts(3, "€" * 60)
    url = "/undo?#{"u" * 1_480}"
    assert_operator url.bytesize, :<=, Admin::BulkResponses::MAX_UNDO_URL
    host.flash_bulk_result(done: posts(2, "A"), refused: refused, verb: "Moved", failed_phrase: "moved to the trash", suffix: " to the trash", undo_url: url)
    assert_nil host.flash[:undo]
    assert_match(/Find them in the Trash\.\z/, host.flash[:warning])
    assert_operator host.flash[:warning].bytesize, :>, host.flash[:warning].length, "the sentences hold multi-byte characters"
  end
end
