require "test_helper"

# The search backends by name and the one `SEARCH_BACKEND` chooses (spec
# §5.2, §5.3). The registry is prepared again after each test, so the
# built-in alone is left.
class SiteSearch::BackendsTest < ActiveSupport::TestCase
  teardown do
    SiteSearch::Backends.forget!
    Rails.application.reloader.prepare!
  end

  def with_search_backend(name)
    was = ENV["SEARCH_BACKEND"]
    name.nil? ? ENV.delete("SEARCH_BACKEND") : ENV["SEARCH_BACKEND"] = name
    SiteSearch::Backends.forget!
    yield
  ensure
    was.nil? ? ENV.delete("SEARCH_BACKEND") : ENV["SEARCH_BACKEND"] = was
    SiteSearch::Backends.forget!
  end

  test "postgres is the default and SEARCH_BACKEND chooses" do
    fake = SiteSearch::Fake.new
    SiteSearch::Backends.register "acme/solr", label: "Solr", backend: -> { fake }

    with_search_backend(nil) { assert_equal "postgres", SiteSearch::Backends.current_name }
    with_search_backend("  ") { assert_equal "postgres", SiteSearch::Backends.current_name }
    with_search_backend("acme/solr") do
      assert_equal "acme/solr", SiteSearch::Backends.current_name
      assert_same fake, SiteSearch::Backends.current
      assert_nil SiteSearch::Backends.check!
    end
    assert_equal %w[postgres acme/solr], SiteSearch::Backends.names
    assert_equal "Postgres", SiteSearch::Backends.label("postgres")
    assert_equal "Solr", SiteSearch::Backends.label("acme/solr")
  end

  test "a name nobody registered stops the boot naming the registered ones" do
    with_search_backend("acme/nope") do
      error = assert_raises(ArgumentError) { SiteSearch::Backends.check! }
      assert_includes error.message, "SEARCH_BACKEND"
      assert_includes error.message, "acme/nope"
      assert_includes error.message, "postgres"
      assert_raises(ArgumentError) { SiteSearch::Backends.current }
    end
  end

  # The built-in is written in the caller's transaction (spec §5.4); an
  # outside engine's call inside a write would hold the write open on the
  # network.
  test "only the built-in may be inline" do
    assert SiteSearch::Backends.inline?("postgres")
    error = assert_raises(ArgumentError) { SiteSearch::Backends.register "acme/solr", label: "Solr", backend: -> { }, inline: true }
    assert_includes error.message, "acme/solr"
    SiteSearch::Backends.register "acme/solr", label: "Solr", backend: -> { }
    assert_not SiteSearch::Backends.inline?("acme/solr")
  end

  test "a name taken and a backend that is not a callable are refused" do
    assert_raises(ArgumentError) { SiteSearch::Backends.register "postgres", label: "Again", backend: -> { } }
    assert_raises(ArgumentError) { SiteSearch::Backends.register "acme/solr", label: "Solr", backend: SiteSearch::Fake.new }
  end

  test "a built backend that does not answer every method of the contract raises a named error" do
    partial = Object.new
    partial.define_singleton_method(:search) { |_query, deadline:| nil }
    partial.define_singleton_method(:health) { |deadline:| nil }
    SiteSearch::Backends.register "acme/partial", label: "Partial", backend: -> { partial }

    with_search_backend("acme/partial") do
      error = assert_raises(SiteSearch::Backends::NotABackend) { SiteSearch::Backends.current }
      assert_includes error.message, "acme/partial"
      assert_includes error.message, "index, remove, prune_record, clear"
      assert_raises(SiteSearch::Backends::NotABackend) { SiteSearch::Backends.current }
    end
  end

  test "whether a backend is inline is its registration's, never a method of the built-in" do
    assert_empty SiteSearch::Backend::METHODS - SiteSearch::Postgres.public_instance_methods
    assert_not SiteSearch::Postgres.new.respond_to?(:inline?)
  end

  # A gem reads its engine's address when the site has chosen it, not when
  # its hook is replayed, and one process holds one backend.
  test "the backend is built once, after the replay" do
    built = 0
    hook = ContentSpiel::Plugins.search_backends do |backends|
      backends.register "acme/counted", label: "Counted", backend: -> { built += 1; SiteSearch::Fake.new }
    end
    Rails.application.reloader.prepare!
    assert_equal 0, built, "the replay registers the callable and does not call it"

    with_search_backend("acme/counted") do
      first = SiteSearch::Backends.current
      assert_same first, SiteSearch::Backends.current
      assert_equal 1, built
    end
  ensure
    ContentSpiel::Plugins.remove(hook) if hook
  end
end
