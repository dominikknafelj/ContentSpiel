require "test_helper"

# Resume-specific field coverage (structured fields, ROLE_TYPES validation)
# moved to test/models/built_in_types_test.rb: those fields now live on the
# `resume_entry` content type's own field schema (open-types spec §3),
# exercised through `Post#assign_fields`/`#fields` rather than the old
# `store_accessor`s this file used to test directly.
class ResumeFieldsTest < ActiveSupport::TestCase
  test "alt texts are translated" do
    root = Page.create!(page_type: :landing, title: "Home", slug: "", published_at: Time.current,
      hero_alt_en: "A desk", hero_alt_de: "Ein Schreibtisch")
    block = root.content_blocks.create!(block_type: :image, position: 0, alt_en: "Chart", alt_de: "Diagramm")

    assert_equal "Ein Schreibtisch", Mobility.with_locale(:de) { root.reload.hero_alt }
    assert_equal "Diagramm", Mobility.with_locale(:de) { block.reload.alt }
  end
end
