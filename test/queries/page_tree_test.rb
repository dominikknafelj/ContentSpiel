require "test_helper"

class PageTreeTest < ActiveSupport::TestCase
  setup { Current.actor = users(:one) }

  # The tree hands each row its address for a find that starts with "/":
  # the page's live path in the editing language, read once for every row.
  test "paths are each page's address in the language, in one statement" do
    with_locales(%w[en de], default: "en") do
      about = create_page(title: "About", translations: { "de" => { title: "Über uns" } })
      team = create_page(title: "Team", parent: about)
      contact = create_page(title: "Contact")
      not_asked = create_page(title: "Not asked")
      ids = [ root_page.id, about.id, team.id, contact.id ]

      english = nil
      statements = capture_sql { english = PageTree.paths(ids, locale: "en") }
      german = PageTree.paths(ids, locale: :de)

      assert_equal 1, statements.size, "the paths cost one statement:\n#{statements.join("\n")}"
      assert_equal "/about", english.fetch(about.id)
      assert_equal "/about/team", english.fetch(team.id)
      assert_equal "/contact", english.fetch(contact.id)
      assert_equal "/", english.fetch(root_page.id)
      assert_equal PublicSite::Paths.current_path(about, "de"), german.fetch(about.id)
      assert_not_equal english.fetch(about.id), german.fetch(about.id)
      assert_not english.key?(not_asked.id), "a page not asked about has no entry"
      assert_empty PageTree.paths([], locale: "en")
    end
  end
end
