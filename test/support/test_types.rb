# Test-only block type, content type and field group (open-types spec §8's
# "open-type proof") -- proof that a plugin, or later an admin-defined type,
# needs nothing but a `register` call plus a ViewComponent to show up
# everywhere a built-in does: rendering, canonical URLs, MCP schemas and
# typed validation. Every name is prefixed with `test/` per spec §3.2a (bare
# names are reserved for built-ins), so these can never collide with a real
# type -- registered or not, `test/quote` is never a name a plugin or an
# admin-defined type would legitimately claim either.
#
# `TestQuoteComponent` lives here, not under `app/components/`, precisely
# because nothing outside this file should ever reference it: it exists only
# to prove `BlockTypeDefinition#component` can point at *any* ViewComponent
# class, including one Rails never autoloads. `erb_template` (ViewComponent's
# inline-template DSL) is what lets it skip a sibling `.html.erb` file
# entirely -- a real type's component wouldn't do this, but this one has no
# other file to live next to.
class TestQuoteComponent < ApplicationComponent
  erb_template <<~ERB
    <blockquote class="content-block content-block--quote">
      <p><%= settings.text %></p>
      <% if settings.cite.present? %><cite><%= settings.cite %></cite><% end %>
    </blockquote>
  ERB

  def initialize(block:, page:)
    @block = block
    @page = page
  end

  private

  attr_reader :block, :page

  # `fallback: true`, not the bare `settings_object` every built-in block
  # component's `block.settings_object` call implicitly skips: a translated
  # `ContentModel::FieldSet` field reads a *literal* locale by default (the
  # admin/MCP rule), and the public site instead needs the same
  # fallback-along-`Locales.fallback_chain` behaviour `Locales.read`/
  # `translated` gives every Mobility-backed column (spec §3.4). There is no
  # `ApplicationComponent#translated` equivalent for a FieldSet's own jsonb
  # storage, so this reads it directly.
  def settings = block.settings_object(fallback: true)
end

# `with_test_types` registers `test/quote` (a block type), `test/event` (a
# content type with a `groups` field) and `test/speaker` (the field group
# `test/event#speakers` embeds), yields, then restores the
# registries via `Rails.application.reloader.prepare!` -- the same call
# `config/initializers/types.rb`'s own `to_prepare` block runs from, which
# resets every registry (`ContentModel::Registry#reset!`) before re-running
# every built-in `register` (see that initializer): a plain `reset!` alone
# would leave the registries empty for whatever test runs next in this
# worker process. `ensure`, not a trailing statement after `yield`, so a test
# failure (an assertion, an unhandled error) still restores the registries
# rather than leaking `test/*` types into every later test in this process.
module TestTypes
  # The two lines every block type declares (block types spec, decision 2),
  # for a type a test registers to look at one other thing.
  def self.declare(t)
    t.theme_methods :block, :page
    t.sample shows: [ "content-block" ]
  end

  # `with_media_list_type { … }`: `test_media_list`, a bare built-in-shaped
  # block type with one `:media_list` field (`images`), which only a block
  # type takes (`ContentModel::FieldTypes::BLOCK_ONLY`). The registry is
  # put back as it was afterwards, so no other test sees the type.
  def with_media_list_type
    saved = BlockTypes.all.dup
    BlockTypes.register("test_media_list") do |t|
      TestTypes.declare(t)
      t.label "Media list"
      t.field :images, :media_list
      t.component TestQuoteComponent
    end
    yield
  ensure
    BlockTypes.reset!
    saved.each { |definition| BlockTypes.registry_put(definition) }
  end

  # A `test_media_list` block on `owner`, written through `ContentBlocks::Save`
  # (which takes the lock order's locks) with these images.
  def media_list_block(owner, images)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: owner), attributes: { block_type: "test_media_list", settings: { "images" => images } })
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def with_test_types
    switched_on_before = SiteSetting.instance.content_types
    BlockTypes.register "test/quote" do |t|
      t.label "Quote"
      t.field :text, :string, required: true, translated: true
      t.field :cite, :url
      # A `groups` schema field on a *block* type (final-fixes round, Task
      # 10/finding 2): no built-in block type declares one, so this is the
      # only fixture that lets `Admin::ContentBlocksController`'s own
      # groups-removal handling be exercised the same way `test/event
      # #speakers` already exercises it for a post's typed `fields`.
      t.field :speakers, :groups, of: "test/speaker"
      t.component TestQuoteComponent
      t.theme_methods :block, :page, :settings
      t.sample settings: { "cite" => "https://example.com/source" },
               translations: { "en" => { text: "A line worth quoting" } },
               shows: [ "A line worth quoting" ]
    end

    FieldGroups.register "test/speaker" do |c|
      c.field :name, :string, required: true
    end

    ContentTypes.register "test/event" do |t|
      t.label "Event"
      t.list_component Posts::BlogListComponent, theme_methods: %w[posts page]
      t.detail_component Posts::DetailComponent, theme_methods: %w[post]
      t.field :venue, :string
      t.field :speakers, :groups, of: "test/speaker"
      t.sample title: "A test event", fields: { venue: "Town hall" }, shows: [ "A test event" ]
    end

    switch_on_registered_types
    yield
  ensure
    Rails.application.reloader.prepare!
    # The switch is put back as it was: `test/event` is gone from the registry,
    # and a name the site holds that nothing declares is no state a test means to leave.
    SiteSetting.instance.update_column(:content_types, switched_on_before)
    Current.site = nil
  end
end
