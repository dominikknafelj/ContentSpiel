require "test_helper"

# The page tree's cost profile with translation markers on (final fix wave,
# I1/T4): the tree is re-rendered after every page-settings autosave, so it
# must cost the same handful of queries however many pages (and blocks) it
# shows, and a re-render after one page's save must not recompute every
# other page's markers (`Translations::CachedStatus`).
class Admin::TreeComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }

  def paragraph(text) = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] } ] }

  def add_pages(count, prefix)
    Array.new(count) do |index|
      page = create_page(title: "#{prefix} #{index}", translations: { "de" => { title: "#{prefix} #{index} (de)" } })
      result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
        translations: { "en" => { body: paragraph("Hello") }, "de" => { body: paragraph("Hallo") } })
      assert result.ok?, result.errors.to_sentence
      page
    end
  end

  def render_tree = render_inline(Admin::TreeComponent.new(root: root_page.reload, locale: "en"))

  # Every statement sent, cached or not (the same counting the tree's
  # access-control query test uses): a per-row query shows up either way.
  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end

  def cache_hits(&block)
    hits = []
    counter = ->(*, payload) { hits.concat(Array(payload[:hits])) }
    ActiveSupport::Notifications.subscribed(counter, "cache_read_multi.active_support", &block)
    hits
  end

  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end

  test "the tree with translation markers costs the same queries for 3 pages as for 15" do
    with_locales(%w[en de es], default: "en") do
      add_pages(3, "Small")
      render_tree # warm up whatever a first render loads once
      small = count_queries { render_tree }

      add_pages(12, "Large")
      large = count_queries { render_tree }

      assert_selector "li.admin-tree-node", minimum: 16
      assert_equal small, large, "the tree ran a query per page"
    end
  end

  test "with a cache, the same holds -- and an unchanged tree is all cache hits" do
    with_memory_cache do
      with_locales(%w[en de es], default: "en") do
        add_pages(3, "Small")
        render_tree
        small = count_queries { render_tree }

        add_pages(12, "Large")
        render_tree
        large = count_queries { render_tree }
        assert_equal small, large, "the tree ran a query per page"
      end
    end
  end

  test "a re-render after one page's save recomputes that page only" do
    with_memory_cache do
      with_locales(%w[en de], default: "en") do
        pages = add_pages(4, "Page")
        render_tree
        listed = Page.count

        assert Pages::Save.call(pages.first, translations: { "en" => { title: "Page 0, revised" } }).ok?
        hits = cache_hits { render_tree }

        assert_equal listed - 1, hits.size, "every page but the saved one is a cache hit"
        assert_selector "li[data-page-id='#{pages.first.id}'] > div [data-translation-marker][title*='Deutsch (outdated)']"
        assert_no_selector "li[data-page-id='#{pages.second.id}'] [data-translation-marker][title*='Deutsch (outdated)']"
      end
    end
  end
end
