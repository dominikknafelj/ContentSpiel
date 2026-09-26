require "test_helper"

class ResumeFieldsTest < ActiveSupport::TestCase
  test "resume fields are stored in metadata" do
    post = Post.create!(content_type: :resume_entry, title: "Engineer",
      company: "Acme", role: "Backend", start_date: "2023-01-01", end_date: "", role_type: "lead")

    assert_equal({ "company" => "Acme", "role" => "Backend", "start_date" => "2023-01-01",
                   "end_date" => "", "role_type" => "lead" }, post.reload.metadata)
    assert_equal "Acme", post.company
  end

  test "role_type must be one of the known types when present" do
    post = Post.new(content_type: :resume_entry, title: "X", role_type: "wizard")

    assert_not post.valid?
    assert post.errors[:role_type].any?
  end

  test "alt texts are translated" do
    root = Page.create!(page_type: :landing, title: "Home", slug: "", published_at: Time.current,
      hero_alt_en: "A desk", hero_alt_de: "Ein Schreibtisch")
    block = root.content_blocks.create!(block_type: :image, position: 0, alt_en: "Chart", alt_de: "Diagramm")

    assert_equal "Ein Schreibtisch", Mobility.with_locale(:de) { root.reload.hero_alt }
    assert_equal "Diagramm", Mobility.with_locale(:de) { block.reload.alt }
  end
end
