require "test_helper"

class ContentModel::ContentTypeDefinitionTest < ActiveSupport::TestCase
  # Same idiom as test/support/test_types.rb: registrations made here are
  # undone by re-running the boot-time registration.
  teardown { Rails.application.reloader.prepare! }

  test "built-in content types get colour indexes in registration order" do
    assert_equal [ 1, 2, 3 ], %w[blog resume_entry now_update].map { |name| ContentTypes.fetch(name).colour_index }
  end

  test "a type may state its own colour index, and the next one skips it" do
    ContentTypes.register("acme/case_study") { |type| type.colour_index = 5 }
    ContentTypes.register("acme/event")
    assert_equal 5, ContentTypes.fetch("acme/case_study").colour_index
    assert_equal 4, ContentTypes.fetch("acme/event").colour_index
  end

  test "a colour index must be a positive integer" do
    assert_raises(ArgumentError) { ContentTypes.register("acme/bad") { |type| type.colour_index = 0 } }
    assert_nil ContentTypes.find("acme/bad")
  end
end
