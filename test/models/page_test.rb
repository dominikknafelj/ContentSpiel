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

  # A blank slug on a non-root page is not a harmless omission: `build_path`
  # drops blank segments, so the page's cached_paths come out identical to its
  # parent's and two pages end up claiming one URL -- for a child of the root,
  # the homepage's "/". Only one of the two can ever be served.
  # No title, since a title present in any locale would now have its slug
  # filled in automatically by `LocalizedSlug` -- this has to be a page with
  # no title at all to still exercise the blank-slug case.
  test "a non-root page requires a slug" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    slugless = Page.new(page_type: :standard, parent: root)

    assert_not slugless.valid?
    assert_includes slugless.errors[:slug], "can't be blank"
  end

  # The failure the validation exists to prevent, stated as the outcome rather
  # than as the error message: no second page may end up holding the
  # homepage's path, and `/` must still belong to the homepage.
  #
  # No title, for the same reason as above: a title would get this page an
  # auto-generated slug and the create would succeed.
  test "a slugless child cannot be saved onto its parent's path" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)

    assert_raises(ActiveRecord::RecordInvalid) do
      Page.create!(page_type: :standard, parent: root, published_at: Time.current)
    end

    assert_equal [ root ], Page.where("cached_paths ->> 'en' = '/'").to_a
    assert_equal root, Page.find_by_full_path(:en, "/")
  end

  # The root is the one page allowed a blank slug: it contributes no segment
  # and its path is "/" by design.
  test "the root page may have a blank slug" do
    root = Page.new(page_type: :standard, title: "Home", slug: "")

    assert root.valid?, root.errors.full_messages.inspect
    assert root.save
    assert_equal "/", root.full_path(:en)
  end

  # Whitespace is blank as far as `build_path`'s `compact_blank` is concerned,
  # so it has to be blank here too -- otherwise " " passes validation and
  # produces the very collision above. No title: with one present,
  # `LocalizedSlug` would treat "   " as not-yet-set (it's blank) and
  # overwrite it with a title-derived slug before this validation ever ran.
  test "a whitespace-only slug does not satisfy the requirement" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    blank = Page.new(page_type: :standard, slug: "   ", parent: root)

    assert_not blank.valid?
    assert_includes blank.errors[:slug], "can't be blank"
  end

  # Task 8c / code-structure review finding #2: a page titled in only one
  # locale used to leave every other locale's slug blank, and a blank
  # non-root slug collapses onto the parent's path (see this file's own
  # comment above `validates :slug` for the two-pages-one-URL bug that
  # produces). LocalizedSlug now fills an untitled locale's slug from the
  # site's default-locale title instead, so the site's own default locale --
  # not the app's fixed English default -- decides the fallback.
  test "slugs for untitled locales fall back to the site's default-locale title" do
    SiteSetting.instance.update!(default_locale: "de")
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)

    child = Mobility.with_locale(:de) { Page.create!(page_type: :standard, title: "Über uns", parent: root) }

    assert_equal "uber-uns", child.slug_en
    assert_equal "uber-uns", child.slug_es
    assert_not_equal root.full_path(:en), child.full_path(:en)
  end

  # When even the default locale has no title, a blank slug is still the wrong
  # answer -- the fallback has to be *some* present title, so it walks
  # Mobility.available_locales and takes the first one it finds.
  test "slugs fall back to the first present title when the default locale has none" do
    SiteSetting.instance.update!(default_locale: "de")
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)

    child = Mobility.with_locale(:es) { Page.create!(page_type: :standard, title: "Sobre Nosotros", parent: root) }

    assert_equal "sobre-nosotros", child.slug_en
    assert_equal "sobre-nosotros", child.slug_de
  end

  # The fallback only ever fills a *blank* slug -- an explicit one, even one
  # written in a locale other than the page's title, is left alone.
  test "an explicitly set slug is kept even when the default-locale fallback would differ" do
    SiteSetting.instance.update!(default_locale: "de")
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)

    child = Mobility.with_locale(:de) do
      Page.create!(page_type: :standard, title: "Über uns", slug_en: "who-we-are", parent: root)
    end

    assert_equal "who-we-are", child.slug_en
  end

  # The fallback can produce a genuine collision, not just a hypothetical one:
  # two siblings can each want the same borrowed slug in a locale neither of
  # them was actually titled in. `slug_is_unused_among_siblings_in_every_locale`
  # (above) still catches it -- reported against `slug_en`, the locale that
  # actually clashes, with a message that names it so an editor filling in a
  # default-locale-only page knows which tab to open.
  test "a fallback-filled slug can produce a real collision, reported against the locale it clashes in" do
    SiteSetting.instance.update!(default_locale: "de")
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    Page.create!(page_type: :standard, title_en: "Team", slug_en: "team", title_de: "Mannschaft", parent: root)

    clashing = Mobility.with_locale(:de) { Page.new(page_type: :standard, title: "Team", parent: root) }

    # Ambient :de throughout: `clashing` is only titled in German, so title
    # presence (a separate, unrelated validation) would otherwise fail under
    # the default :en and mask the assertions this test actually cares about.
    Mobility.with_locale(:de) do
      assert_not clashing.valid?
      assert_includes clashing.errors[:slug_en], "has already been taken in EN"
      assert_empty clashing.errors[:slug_de], "the pages only clash in English, not German"

      clashing.slug_en = "team-2"
      assert clashing.valid?, clashing.errors.full_messages.inspect
    end
  end

  # The slug validation above closes the route by which two pages could come to
  # share a path from the admin. Should it ever happen some other way, the
  # lookup still has to name one winner, and the same one every time -- and the
  # winner is the older page, so a URL already in use is not taken over by a
  # page created later.
  #
  # This holds because `find_by_full_path` orders by `id`. (ActiveRecord's
  # `.first` already appends an implicit `ORDER BY id ASC` to an unordered
  # relation, so the emitted SQL is identical either way -- the explicit
  # `.order(:id)` states the guarantee this test depends on locally, instead of
  # resting it on that implementation detail.)
  test "a path claimed by two pages resolves to the older one" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    incumbent = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root,
      published_at: Time.current)
    latecomer = Page.create!(page_type: :standard, title: "Also About", slug: "also-about", parent: root,
      published_at: Time.current)

    # Written past the validations on purpose: this is the state the lookup has
    # to survive, not a state the admin can now produce.
    latecomer.update_columns(cached_paths: incumbent.cached_paths)

    assert_equal incumbent, Page.find_by_full_path(:en, "/about")
  end

  test "slug is unique among siblings, scoped to locale" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)
    duplicate = Page.new(page_type: :standard, title: "Also About", slug: "about", parent: root)

    assert_not duplicate.valid?
    # Attributed to the locale that actually collides, so the admin form can
    # mark that locale's tab.
    assert_includes duplicate.errors[:slug_en], "has already been taken in EN"
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
    # A German title of its own, so its real German slug is "kontakt" rather
    # than a default-locale fallback of "about" -- otherwise this sibling
    # would already hold "about" in German too (Task 8c), and the collision
    # below would be a real one instead of the false one this test guards
    # against.
    Page.create!(page_type: :standard, title_en: "About", slug_en: "about", title_de: "Kontakt", parent: root)

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
    assert_includes duplicate.errors[:slug_de], "has already been taken in DE"
    assert_empty duplicate.errors[:slug_en]
  end

  # Reading `slug` in a locale the page has no slug for returns the English one
  # via fallback. Validating *that* string as if it were the German slug would
  # collide a page with a German slug it does not actually have -- which is
  # exactly why the validation below reads the literal per-locale accessor and
  # skips a genuinely blank one, rather than reading through Mobility's
  # fallback.
  #
  # Task 8c means a *titled* page can no longer reach this validation with a
  # genuinely blank slug in any locale -- `LocalizedSlug` fills one from a
  # title the moment any title exists anywhere on the page. `update_columns`
  # forces the untitled, pre-fill state a row predating that feature (or a
  # bulk import) could still be in, the same way the "bypassed" tests further
  # down force other pre/post-validation states.
  test "a page with no slug anywhere is not blocked by a sibling's slug in the current locale" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    untitled = Page.create!(page_type: :standard, title: "Placeholder", parent: root)
    untitled.update_columns(title: {}, slug: {})
    german = Page.create!(page_type: :standard, title: "Contact", slug: "contact", parent: root)
    Mobility.with_locale(:de) { german.update!(slug: "about") }

    Mobility.with_locale(:de) do
      untitled.valid?
      assert_empty untitled.errors[:slug_de],
        "a page without a German slug of its own must not collide on a sibling's German slug"
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
    # A German title of its own, so "about" isn't also this sibling's real
    # German slug (Task 8c's default-locale fallback would otherwise put it
    # there) -- the point here is the *other* page's German slug, not a
    # same-locale collision with this one.
    Page.create!(page_type: :standard, title_en: "About", slug_en: "about", title_de: "Kontakt", parent: root)
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

  # The root is the homepage: it contributes no path segment of its own, so it
  # answers to "/" no matter what slug it carries.
  test "full_path is computed from the page's own slug for a root page" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")

    assert_equal "/", root.full_path(:en)
  end

  test "full_path concatenates ancestor slugs" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    section = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)
    leaf = Page.create!(page_type: :standard, title: "Team", slug: "team", parent: section)

    # A child of the root is "/about", not "//about".
    assert_equal "/about", section.full_path(:en)
    assert_equal "/about/team", leaf.full_path(:en)
  end

  test "full_path differs per locale when slugs are translated" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    page = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)
    Mobility.with_locale(:de) { page.update!(title: "Ueber uns", slug: "ueber-uns") }

    assert_equal "/about", page.full_path(:en)
    assert_equal "/ueber-uns", page.full_path(:de)
  end

  # Spec section 6: a page missing a translation falls back to the default
  # locale. A German path built from a literal German slug the page doesn't
  # have would be "/ueber-uns/" -- a hole where a segment should be.
  test "full_path falls back to the default locale for an untranslated slug" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    section = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)
    Mobility.with_locale(:de) { section.update!(slug: "ueber-uns") }
    leaf = Page.create!(page_type: :standard, title: "Team", slug: "team", parent: section)

    assert_equal "/ueber-uns/team", leaf.full_path(:de)
  end

  test "find_by_full_path locates the matching page" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    page = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root, published_at: Time.current)

    assert_equal page, Page.find_by_full_path(:en, "/about")
    assert_equal root, Page.find_by_full_path(:en, "/")
    assert_nil Page.find_by_full_path(:en, "/does-not-exist")
  end

  # The lookup is scoped to one locale's key: an English path must not resolve
  # for a German visitor just because some page holds it in English.
  test "find_by_full_path only matches the requested locale" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    page = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root, published_at: Time.current)
    Mobility.with_locale(:de) { page.update!(slug: "ueber-uns") }

    assert_equal page, Page.find_by_full_path(:de, "/ueber-uns")
    assert_nil Page.find_by_full_path(:de, "/about")
  end

  # The lookup is what the public site routes through, so it answers for
  # published pages only -- a draft is invisible at its own path, the same way
  # an unpublished Post is absent from a post_list.
  test "find_by_full_path ignores unpublished pages" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    draft = Page.create!(page_type: :standard, title: "Draft", slug: "draft", parent: root, published_at: nil)
    Page.create!(page_type: :standard, title: "Scheduled", slug: "scheduled", parent: root, published_at: 1.day.from_now)

    assert_nil Page.find_by_full_path(:en, "/draft")
    assert_nil Page.find_by_full_path(:en, "/scheduled")

    draft.update!(published_at: 1.minute.ago)
    assert_equal draft, Page.find_by_full_path(:en, "/draft")
  end

  test "updating a slug recomputes cached_paths for the page and its descendants" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    section = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)
    leaf = Page.create!(page_type: :standard, title: "Team", slug: "team", parent: section)

    section.update!(slug: "company")

    assert_equal "/company", section.reload.full_path(:en)
    assert_equal "/company/team", leaf.reload.full_path(:en)
  end

  # The cascade has to reach the whole subtree, not just the direct children:
  # a grandchild's path is shifted by its grandparent's slug just as much.
  test "updating a slug recomputes cached_paths for indirect descendants too" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    section = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)
    team = Page.create!(page_type: :standard, title: "Team", slug: "team", parent: section)
    member = Page.create!(page_type: :standard, title: "Ada", slug: "ada", parent: team)

    section.update!(slug: "company")

    assert_equal "/company/team/ada", member.reload.full_path(:en)
  end

  # Every locale is recomputed, not just `Mobility.locale`: the cascade runs
  # once, under whatever locale happened to be current for the edit.
  test "recomputing paths covers every available locale" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    section = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)
    leaf = Page.create!(page_type: :standard, title: "Team", slug: "team", parent: section)
    Mobility.with_locale(:de) { section.update!(slug: "ueber-uns") }

    # Sorted because jsonb does not preserve insertion order of keys.
    assert_equal %w[de en es], leaf.reload.cached_paths.keys.sort
    assert_equal "/ueber-uns/team", leaf.full_path(:de)
    assert_equal "/about/team", leaf.full_path(:en)
  end

  # A page's path changes when it moves, even though none of its own slugs did.
  test "moving a page recomputes cached_paths for it and its descendants" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    origin = Page.create!(page_type: :standard, title: "Origin", slug: "origin", parent: root)
    destination = Page.create!(page_type: :standard, title: "Destination", slug: "destination", parent: root)
    section = Page.create!(page_type: :standard, title: "About", slug: "about", parent: origin)
    leaf = Page.create!(page_type: :standard, title: "Team", slug: "team", parent: section)

    section.update!(parent: destination)

    assert_equal "/destination/about", section.reload.full_path(:en)
    assert_equal "/destination/about/team", leaf.reload.full_path(:en)
  end

  test "cached_paths is populated on create" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "")
    page = Page.create!(page_type: :standard, title: "About", slug: "about", parent: root)

    assert_equal({ "en" => "/about", "de" => "/about", "es" => "/about" }, page.reload.cached_paths)
  end
end
