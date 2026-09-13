require "test_helper"

class PageTest < ActiveSupport::TestCase
  test "title is required" do
    page = Page.new(page_type: :standard)
    assert_not page.valid?
    assert_includes page.errors[:title], "can't be blank"
  end

  test "page_type is an enum with standard and landing" do
    page = Page.create!(page_type: :landing, title: "Home")

    assert page.landing?
    assert_equal %w[standard landing], Page.page_types.keys
  end

  test "a page can have a parent and children" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    child = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)

    assert_equal root, child.parent
    assert_includes root.children, child
  end

  # closure_tree's whole point is the hierarchy table: ancestors/descendants
  # are answered by a join, not by walking parent_id in Ruby.
  test "descendants and ancestors span more than one generation" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    section = Page.create!(page_type: :standard, title: "Section", slug: "section", parent: root)
    leaf = Page.create!(page_type: :standard, title: "Team", slug: "team", parent: section)

    assert_equal [ section, leaf ], root.descendants.to_a
    assert_equal [ section, root ], leaf.ancestors.to_a
    assert_equal 2, leaf.depth
  end

  # closure_tree maintains the ordering column itself; siblings come back in
  # that order rather than in insertion or id order.
  test "siblings are ordered by a position column closure_tree maintains" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    first = Page.create!(page_type: :standard, title: "First", slug: "first", parent: root)
    second = Page.create!(page_type: :standard, title: "Second", slug: "second", parent: root)

    assert_equal [ 0, 1 ], [ first.reload.position, second.reload.position ]

    second.update!(position: -1)

    assert_equal [ second, first ], root.reload.children.to_a
  end

  test "only one page may have no parent" do
    Page.create!(page_type: :standard, title: "Home", slug: "")
    second_root = Page.new(page_type: :standard, title: "Also Home", slug: "also-home")

    assert_not second_root.valid?
    assert_includes second_root.errors[:base], "a root page already exists"
  end

  # The root check excludes the record itself, or the one legitimate root would
  # fail validation on every subsequent save.
  test "the existing root page stays valid on update" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")

    root.title = "Homepage"

    assert root.valid?, root.errors.full_messages.inspect
    assert root.save
  end

  # A create-only check would let a second root in through the back door by
  # detaching an existing child.
  test "an existing child cannot be promoted to a second root" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    child = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)

    child.parent = nil

    assert_not child.valid?
    assert_includes child.errors[:base], "a root page already exists"
  end

  test "slug is unique among siblings, scoped to locale" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)
    duplicate = Page.new(page_type: :standard, title: "Also About", slug: "about", parent: root)

    assert_not duplicate.valid?
    # Attributed to the locale that actually collides, so the admin form can
    # mark that locale's tab.
    assert_includes duplicate.errors[:slug_en], "has already been taken"
  end

  test "the same slug is allowed under a different parent" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    section_a = Page.create!(page_type: :standard, title: "Section A", slug: "section-a", parent: root)
    section_b = Page.create!(page_type: :standard, title: "Section B", slug: "section-b", parent: root)
    Page.create!(page_type: :standard, title: "Team", slug: "team", parent: section_a)
    other_team = Page.new(page_type: :standard, title: "Team", slug: "team", parent: section_b)

    assert other_team.valid?, other_team.errors.full_messages.inspect
  end

  test "the same slug is allowed among siblings in different locales" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)

    Mobility.with_locale(:de) do
      other = Page.new(page_type: :standard, title: "Ueber uns", slug: "about", parent: root)
      assert other.valid?, "a slug used in one locale must not block the same slug in another locale"
    end
  end

  # The admin form submits every locale's slug in one request, under one
  # ambient locale. Validating only `Mobility.locale` lets the other locales'
  # slugs through to the database, where the per-locale unique indexes turn a
  # would-be form error into an unhandled RecordNotUnique.
  test "a sibling slug duplicated in a locale other than the current one is rejected" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    existing = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)
    Mobility.with_locale(:de) { existing.update!(slug: "ueber-uns") }

    duplicate = Page.new(page_type: :standard, title: "Contact", slug: "contact", parent: root)
    duplicate.slug_de = "ueber-uns"

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug_de], "has already been taken"
    assert_empty duplicate.errors[:slug_en]
  end

  # Reading `slug` in a locale the page has no slug for returns the English one
  # via fallback. Validating *that* string as if it were the German slug makes
  # a page collide with a German slug it does not actually have.
  test "a page with no slug in the current locale is not blocked by a sibling's slug there" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    english_only = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)
    german = Page.create!(page_type: :standard, title: "Contact", slug: "contact", parent: root)
    Mobility.with_locale(:de) { german.update!(slug: "about") }

    Mobility.with_locale(:de) do
      assert english_only.valid?,
        "a page without a German slug must not collide on a sibling's German slug"
    end
  end

  test "a page does not collide with its own slug on update" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    child = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)

    assert child.valid?
    Mobility.with_locale(:de) do
      child.slug = "ueber-uns"
      assert child.valid?
    end
  end

  test "a page with children cannot be destroyed" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    child = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)

    assert_not root.destroy
    assert_includes root.errors[:base], "cannot delete a page that still has children"
    assert Page.exists?(root.id)
    # closure_tree's default `dependent: :nullify` would have orphaned the child
    # into a second root before we ever got to refuse the destroy.
    assert_equal root, child.reload.parent
    assert_equal 1, PageHierarchy.where(ancestor_id: root.id, descendant_id: child.id).count
  end

  test "a childless page can be destroyed" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    child = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)

    assert child.destroy
    assert_empty PageHierarchy.where(descendant_id: child.id)
  end

  test "title, slug, subtitle and meta fields are independently translatable" do
    page = Page.create!(
      page_type: :standard, title: "About", slug: "about",
      subtitle: "Who we are", meta_title: "About us", meta_description: "A short bio"
    )

    Mobility.with_locale(:de) do
      page.update!(title: "Ueber uns", slug: "ueber-uns", subtitle: "Wer wir sind",
        meta_title: "Ueber uns", meta_description: "Eine kurze Biografie")
    end

    reloaded = Page.find(page.id)

    assert_equal "About", reloaded.title
    assert_equal "about", reloaded.slug
    assert_equal "Who we are", reloaded.subtitle
    assert_equal "About us", reloaded.meta_title
    assert_equal "A short bio", reloaded.meta_description
    Mobility.with_locale(:de) do
      assert_equal "Ueber uns", reloaded.title
      assert_equal "ueber-uns", reloaded.slug
      assert_equal "Wer wir sind", reloaded.subtitle
      assert_equal "Ueber uns", reloaded.meta_title
      assert_equal "Eine kurze Biografie", reloaded.meta_description
    end
  end

  # Proves the jsonb backend is what's storing these -- every locale lives in
  # one column on the pages row, not in a side table.
  test "translated attributes are stored in a jsonb column per attribute" do
    page = Page.create!(page_type: :standard, title: "About", slug: "about")
    Mobility.with_locale(:de) { page.update!(title: "Ueber uns") }

    raw = Page.connection.select_one("SELECT title FROM pages WHERE id = #{page.id}")

    assert_equal({ "en" => "About", "de" => "Ueber uns" }, JSON.parse(raw["title"]))
  end

  test "hero_image is an Active Storage attachment" do
    page = Page.create!(page_type: :standard, title: "About", slug: "about")

    page.hero_image.attach(
      io: StringIO.new("not really a jpeg"), filename: "hero.jpg", content_type: "image/jpeg"
    )

    assert page.hero_image.attached?
    assert_equal "hero.jpg", page.reload.hero_image.filename.to_s
  end

  test "published_at records when a page went live" do
    at = Time.current.change(usec: 0)
    page = Page.create!(page_type: :standard, title: "About", slug: "about", published_at: at)

    assert_equal at, page.reload.published_at
  end

  # The validation is the first line of defense; these indexes are the second.
  test "the database rejects a same-locale duplicate sibling slug when validation is bypassed" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)
    sneaky = Page.create!(page_type: :standard, title: "Contact", slug: "contact", parent: root)

    assert_raises ActiveRecord::RecordNotUnique do
      Page.transaction(requires_new: true) do
        sneaky.update_column(:slug, { "en" => "about" })
      end
    end
  end

  test "the database allows the same sibling slug in two different locales" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)
    other = Page.create!(page_type: :standard, title: "Contact", slug: "contact", parent: root)

    other.update_column(:slug, { "en" => "contact", "de" => "about" })

    assert_equal "about", Mobility.with_locale(:de) { Page.find(other.id).slug }
  end

  test "the database allows the same slug under a different parent" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    section = Page.create!(page_type: :standard, title: "Section", slug: "section", parent: root)
    Page.create!(page_type: :standard, title: "Team", slug: "team", parent: root)
    other = Page.create!(page_type: :standard, title: "Team", slug: "crew", parent: section)

    other.update_column(:slug, { "en" => "team" })

    assert_equal "team", Page.find(other.id).slug
  end
end
