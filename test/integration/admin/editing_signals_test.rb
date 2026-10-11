require "test_helper"

# `Admin::BaseController` reads `X-Notes-Tab` for every admin request into
# `Current.editing_tab`, so the signal a content write causes names the tab.
class Admin::EditingSignalsTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    @page = create_page(title: "Pricing", published: false)
    @block = @page.content_blocks.create!(block_type: "post_list", position: 0)
    @stream = Editing::Signals.record_stream(@page)
  end

  def save_block(limit, headers)
    patch "/cs-studio/pages/#{@page.id}/content_blocks/#{@block.id}",
      params: { block: { settings: { limit: limit } }, base_updated_at: @block.reload.updated_at.iso8601(6) }, headers:, as: :turbo_stream
    assert_response :success
  end

  def sent = broadcasts(@stream).map { |payload| ActiveSupport::JSON.decode(payload) }

  test "a well-formed tab id is the origin of the signal a save causes, and a malformed one gives none" do
    save_block("3", { "X-Notes-Tab" => "0f8fad5b-d9cb-469f-a165-70867728950e" })
    save_block("4", { "X-Notes-Tab" => "<img src=x>" })
    save_block("5", {})

    assert_equal "0f8fad5b-d9cb-469f-a165-70867728950e", sent.first["origin"]
    assert_equal [ %w[content_block_id kind reason] ] * 2, sent.drop(1).map { |signal| signal.keys.sort }
  end
end
