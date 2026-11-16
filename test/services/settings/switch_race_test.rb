require "test_helper"

# A publish and a switch-off of its post's type on two connections at once:
# the publish holds the settings row `FOR SHARE` (`ContentTypes.hold!`) and
# the switch takes it `FOR UPDATE` first (`Settings::Save`), so whichever
# comes second waits for the first's commit and decides from it. The
# statement order on one connection is `Posts::SwitchHoldTest`.
#
# Two connections need rows the other can see, so this class runs outside the
# test transaction (in the style of `Publishing::VersionRaceTest`). Its rows
# are made through the models and removed in `clean`; the settings row's
# switches are put back as they were. `Audit.record` is replaced for the
# class's tests: the log is append-only, and an event committed here would
# stay for every later test.
class Settings::SwitchRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @types = SiteSetting.instance.content_types
    clean
    root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
    everything = Page.create!(parent: root, title: "Everything", published_at: 1.day.ago)
    everything.content_blocks.create!(block_type: :post_list, position: 0, settings: {})
    @audit = Audit.method(:record)
    Audit.define_singleton_method(:record) { |*, **| nil }
    @post = Posts::Save.call(attributes: { content_type: "resume_entry", published: false }, translations: { "en" => { title: "Lighthouse keeper" } }).record
    assert @post.persisted?
  end

  teardown do
    Audit.define_singleton_method(:record, @audit) if @audit
    clean
    SiteSetting.instance.update!(content_types: @types)
    Current.reset
  end

  def clean
    Post.find_each { |post| post.published_versions.delete_all } # version: none (a test's own rows)
    Post.find_each(&:destroy)
    Page.find_each { |page| page.published_versions.delete_all } # version: none (a test's own rows)
    Page.where.not(parent_id: nil).find_each(&:destroy!)
    Page.where(parent_id: nil).find_each(&:destroy!)
    SiteSearch::Word.delete_all
    Current.reset
  end

  # `first` runs in a transaction that stays open; `second` is started on
  # another connection, and waited for until Postgres says it is blocked on a
  # lock by a statement that matches `waiting`; then the first commits and
  # the second goes on.
  def behind(first, second, waiting:)
    thread = nil
    first_answer = SiteSetting.transaction do
      answer = first.call
      thread = Thread.new { ActiveRecord::Base.connection_pool.with_connection { Current.reset; second.call } }
      await_blocked(waiting)
      answer
    end
    [ first_answer, thread.value ]
  ensure
    thread&.join
  end

  def await_blocked(waiting)
    sql = "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock' AND query LIKE #{ActiveRecord::Base.connection.quote(waiting)}"
    200.times do
      return if Thread.new { ActiveRecord::Base.connection_pool.with_connection { ActiveRecord::Base.connection.select_value(sql).to_i.positive? } }.value

      sleep 0.025 # sleep: polling Postgres for the second statement to be waiting on the first's lock
    end
    flunk "the second statement never blocked behind the first"
  end

  def switch_off = -> { Settings::Save.call(SiteSetting.instance, attributes: { content_types: %w[blog now_update] }) }
  def publish = -> { Posts::Save.call(Post.find(@post.id), attributes: { published: true }) }

  test "a publish that arrives while a switch-off is in flight waits for it and is refused" do
    switched, published = behind(switch_off, publish, waiting: "%site_settings%FOR SHARE%")

    assert switched.ok?, switched.errors.inspect
    assert_equal :switched_off, published.refusal
    assert_nil @post.reload.published_at
    assert_not PublicPath.current.where(record: @post).exists?
    assert_not SiteSearch::Entry.where(record_type: "Post", record_id: @post.id).exists?
  end

  test "a switch-off that arrives while a publish is in flight waits for it and takes the address it gave" do
    published, switched = behind(publish, switch_off, waiting: "%site_settings%FOR UPDATE%")

    assert published.ok?, published.errors.inspect
    assert switched.ok?, switched.errors.inspect
    assert @post.reload.published_at, "the publish stood"
    assert_not PublicPath.current.where(record: @post).exists?, "the switch-off took the address the publish gave"
    assert SiteSearch::IndexState.empty_or_stale?(SiteSearch::Backends.current_name, site: SiteSetting.instance), "the switch made the index stale, so its rebuild drops the post's entries"
  end
end
