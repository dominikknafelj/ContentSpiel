require "test_helper"

class Dashboard::TranslationNeedsTest < ActiveSupport::TestCase
  setup { with_locales(%w[en de], default: "en") }

  def german = Dashboard::TranslationNeeds.new(actor: users(:one), channel: :admin).entries.find { |entry| entry.locale == "de" }

  test "a dormant post is in none of the dashboard's lists" do
    Translations::StateIndex.rebuild_all
    kept = create_post(title: "Kept")
    dormant = create_post(title: "Dormant", content_type: "resume_entry")
    [ kept, dormant ].each do |post|
      assert Posts::Save.call(post, translations: { "de" => { title: "#{post.title} (de)" } }).ok?
      assert Posts::Save.call(post, translations: { "en" => { title: "#{post.title}!" } }).ok?
    end
    before = german
    assert_equal dormant, before.item.last

    switch_on_content_types("blog")

    after = german
    assert_equal before.total - 1, after.total
    assert_equal kept, after.item.last
  end
end
