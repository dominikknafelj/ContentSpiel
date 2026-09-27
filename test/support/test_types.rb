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
  def with_test_types
    BlockTypes.register "test/quote" do |t|
      t.label "Quote"
      t.field :text, :string, required: true, translated: true
      t.field :cite, :url
      t.component TestQuoteComponent
    end

    FieldGroups.register "test/speaker" do |c|
      c.field :name, :string, required: true
    end

    ContentTypes.register "test/event" do |t|
      t.label "Event"
      t.color "#f59e0b"
      t.list_component Posts::BlogListComponent
      t.detail_component Posts::DetailComponent
      t.field :venue, :string
      t.field :speakers, :groups, of: "test/speaker"
    end

    yield
  ensure
    Rails.application.reloader.prepare!
  end
end
