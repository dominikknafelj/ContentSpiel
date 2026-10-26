require "test_helper"

class PublicStringsTest < ActiveSupport::TestCase
  # The test stores a German word into the shared backend; reloading puts the
  # files' translations back for every test that follows.
  teardown { I18n.reload! }

  test "a key the visitor's language has is read in it, and one it lacks is English" do
    I18n.backend.store_translations(:de, public: { site: { tagged: "Verschlagwortet" } })

    I18n.with_locale(:de) do
      assert_equal "Verschlagwortet", PublicStrings.read("public.site.tagged")
      assert_equal "In this section", PublicStrings.read("public.site.in_this_section")
    end
  end
end
