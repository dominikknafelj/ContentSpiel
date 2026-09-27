# Open Types Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the closed block-type and content-type enums with string types backed by code registries (`BlockTypes`, `ContentTypes`, `FieldGroups`) that carry a declarative field schema, give blocks a polymorphic owner, and render blocks and post lists through view components the registry points to.

**Architecture:** Definitions are plain Ruby objects registered from `config/initializers/types.rb` (`to_prepare`). A `ContentModel::FieldSet` builder turns a definition's field schema into an ActiveModel class that casts, validates and serializes values stored in jsonb (`settings`/`translated_settings` on blocks, `metadata`/`translated_metadata` on posts). Everything that knows about a specific type asks the registry instead: rendering, canonical URLs, MCP, starter content, Avo and the mind graph. ViewComponent replaces the block and post-list partials.

**Tech Stack:** Rails 8.1, Ruby 3.4, Postgres jsonb, Mobility 1.3, ActiveModel::Attributes, `view_component` (new gem), `lookbook` (new gem, development/test only), Minitest + fixtures, Avo 4 (transitional).

**Spec:** `docs/superpowers/specs/2026-09-27-open-types-design.md` (binding). Earlier foundations spec for context: `docs/superpowers/specs/2026-09-26-foundations-design.md`.

## Global Constraints

- **Greenfield, no production.** Migrations drop and rebuild; no backfill, no compatibility shims. `bin/rails db:reset` must succeed afterwards, and seeds rebuild `public_paths`.
- **Registration.** Built-ins register from `config/initializers/types.rb` inside `Rails.application.config.to_prepare`, and the registries reset at the start of each run. Plugins will use the same `register` calls; the DSL is out of scope.
- **Field types:** exactly `string text integer boolean date url select content_type tag component components`.
  - Options: `required default min max translated options of`.
  - A component's own fields may not be `group`/`groups` (one level).
  - No dynamic zones.
- **Translated field storage.** Values live in `translated_settings` / `translated_metadata` as `{ locale => { key => value } }`. A translated `group`/`groups` field is translated as a whole.
- **Reads.** Public reads fall back along `Locales.fallback_chain`; admin and MCP read the literal locale.
- **Existing columns stay columns** (block `body`/`caption`/`alt`/`image`; post `title`/`slug`/`excerpt`/`body`). A type opts into them with `uses`. ActionText is untouched (Tiptap is sub-project 4).
- **Enums.** `page_type` stays an integer enum. No new integer enums anywhere.
- **Unknown stored types never 500 the public site.** Render boundaries and path sync use `find` and skip with a logged warning; `fetch` raises `ContentModel::UnknownType`.
- **Components.** View components live in `app/components/`, take explicit keyword inputs, and read no controller instance variables. Lookbook is mounted only in development at `/lookbook`.
- **Patterns from the foundations sub-project apply:**
  - services return `ApplicationService::Result`;
  - public text goes through `Locales.read` / `ThemeHelper#translated`;
  - public URLs only through `PublicSite::Urls`;
  - `public_paths` is maintained from model callbacks;
  - the "don't touch" rules for `Page` callback order stay.
- **No Page/Post fixtures.** Use the helpers in `test/support/content_helper.rb` (`root_page`, `create_page`, `create_post`, `with_locales`) or `Page.create!`/`Post.create!` in code.
- **Comments.** Long, load-bearing comments are the norm (CLAUDE.md). Move existing comments with the code they describe and keep them true.
- **Tests:** `PARALLEL_WORKERS=1 bin/rails test`, and `bin/rails test test/system` run alone (shared test DB: never two test processes at once).
- **Lint:** `bin/rubocop` on changed files; `bin/brakeman -q --no-pager` clean; `bin/rails zeitwerk:check` clean.
- **Commits:** conventional, each ending with exactly `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never skip hooks.

## Review Focus

1. **A post list whose `content_type` is blank (lists every type).** It must render all types in one list, using the default (blog) row component, not crash or render nothing. Pinned in Task 4, step 1: `test "an unfiltered post list renders every type with the default rows"`.
2. **A stored block or post whose type is no longer registered.** The public page must still render (skipping that block), post path sync must skip that post, and neither may raise. Pinned in Task 2, step 1: `test "an unregistered stored block type is skipped on render and sync"`.
3. **Blank form values for typed fields** (`limit: ""`, `start_date: ""`). They must be stored as absent, not `""` or `0`, so "blank = no limit / current role" keeps working. Pinned in Task 1, step 1: `test "blank strings cast to nil for every scalar type"`.
4. **A translated field written in one locale and read in another on the public site.** It must fall back along the site's chain; admin and MCP must see the literal (blank) value. Pinned in Task 1, step 1: `test "translated field reads fall back publicly and stay literal otherwise"`.
5. **Registries after code reload in development.** Types must still be registered exactly once (no duplicates, no "unknown type" after an edit); registering a taken name outside a reset raises `ContentModel::DuplicateType`. Pinned in Task 1, step 1: `test "re-registering replaces the definition and reset! clears"`, plus the `to_prepare` reset in Task 2.

---

### Task 1: Field schema, `ContentModel::FieldSet` and the registries

Spec: §3.

**Files:**
- Create:
  - `app/models/type_registry.rb`
  - `app/models/type_definition.rb`
  - `app/models/block_type_definition.rb`
  - `app/models/content_type_definition.rb`
  - `app/models/component_definition.rb`
  - `app/models/block_types.rb`
  - `app/models/content_types.rb`
  - `app/models/components.rb`
  - `app/models/field_set.rb`
- Test:
  - `test/models/type_registry_test.rb`
  - `test/models/field_set_test.rb`

**Interfaces:**
- **Produces:**
  - `BlockTypes` / `ContentTypes` / `FieldGroups` (modules extending `ContentModel::Registry`), with:
    - `.register(name) { |t| … }`, which returns the definition;
    - `.fetch(name)`, which raises `ContentModel::UnknownType`;
    - `.find(name)`, which returns nil for an unknown name;
    - `.names` (Array of String), `.all`, `.reset!`;
    - `BlockTypes.with_capability(sym)`;
    - `ContentTypes.default`, the first registered content type definition.
  - **`ContentModel::Definition` DSL:**
    - `label(str)`, `field(name, type, **opts)`, `uses(*columns)`, `capability(*syms)`;
    - readers `name`, `label`, `fields` (Array of `ContentModel::Definition::Field`), `uses_columns`, `capability?(sym)`, `field_set` (the built class).
  - **`ContentModel::BlockContentModel::Definition`:** `component(klass)` → `#component`.
  - **`ContentModel::ContentContentModel::Definition`:**
    - `color(hex)`, `list_component(klass)`, `detail_component(klass)`, `starter(section:, sample:)`;
    - the matching readers.
  - **`ContentModel::FieldGroupDefinition`:** `component(klass)` for rendering a field group.
  - **`ContentModel::Definition::Field`** = `Data.define(:name, :type, :options)` with `#translated?`, `#required?`, `#group?`.
  - **`ContentModel::FieldSet.for(definition)`** returns an ActiveModel class. Instances are built with `new(values = {}, translations = {}, locale: nil, fallback: false)`, where `values` holds untranslated keys and `translations` is `{ locale => hash }`. They offer:
    - a reader per field;
    - `#valid?` / `#errors`, keyed by path like `limit`, `speakers.1.name`;
    - `#untranslated_hash` and `#translated_hash`, the JSON-ready hashes of each group;
    - `#assign(hash)`, which casts and sets keys for the instance's locale;
    - `#component(name)`, which returns the nested instance or an Array of instances.

- [ ] **Step 1: Write the failing tests**

`test/models/type_registry_test.rb`:

```ruby
require "test_helper"

class ContentModel::RegistryTest < ActiveSupport::TestCase
  setup do
    @saved = BlockTypes.all.dup
    BlockTypes.reset!
  end

  teardown do
    BlockTypes.reset!
    @saved.each { |definition| BlockTypes.registry_put(definition) }
  end

  test "register, fetch, find, names and capabilities" do
    BlockTypes.register(:quote) { |t| t.label "Quote"; t.field :cite, :string; t.capability :lists_posts }
    assert_equal %w[quote], BlockTypes.names
    assert_equal "Quote", BlockTypes.fetch(:quote).label
    assert_nil BlockTypes.find("nope")
    assert_raises(ContentModel::UnknownType) { BlockTypes.fetch("nope") }
    assert_equal %w[quote], BlockTypes.with_capability(:lists_posts).map(&:name)
  end

  test "re-registering replaces the definition and reset! clears" do
    BlockTypes.register(:quote) { |t| t.label "Old" }
    BlockTypes.register(:quote) { |t| t.label "New" }
    assert_equal [ "New" ], BlockTypes.all.map(&:label)
    BlockTypes.reset!
    assert_empty BlockTypes.names
  end

  test "unknown field types and nested components are rejected at registration" do
    assert_raises(ArgumentError) { BlockTypes.register(:x) { |t| t.field :a, :colour } }
    assert_raises(ArgumentError) { FieldGroups.register(:bad) { |c| c.field :inner, :group, of: :cta } }
  end
end
```

`registry_put` is a small test seam that puts a definition back unchanged. Define it in `ContentModel::Registry` as a public method named exactly `registry_put`, with a comment saying it's for tests restoring state.

`test/models/field_set_test.rb`:

```ruby
require "test_helper"

class ContentModel::FieldSetTest < ActiveSupport::TestCase
  setup do
    @definition = ContentModel::ContentContentModel::Definition.new("event").tap do |t|
      t.field :venue, :string, required: true
      t.field :seats, :integer, min: 1
      t.field :starts_on, :date
      t.field :website, :url
      t.field :kind, :select, options: { "talk" => "Talk", "workshop" => "Workshop" }
      t.field :listed, :boolean, default: true
      t.field :headline, :string, translated: true
    end
    FieldGroups.register(:speaker) { |c| c.field :name, :string, required: true; c.field :url, :url }
    @with_components = ContentModel::ContentContentModel::Definition.new("conference").tap do |t|
      t.field :speakers, :groups, of: :speaker
      t.field :lead, :group, of: :speaker, translated: true
    end
  end

  teardown { FieldGroups.reset! ; Rails.application.reloader.prepare! }

  test "casts, defaults and validates scalar fields" do
    fields = ContentModel::FieldSet.for(@definition).new({ "venue" => "Hall", "seats" => "12", "starts_on" => "2026-10-01", "kind" => "talk" })
    assert fields.valid?, fields.errors.full_messages.to_sentence
    assert_equal 12, fields.seats
    assert_equal Date.new(2026, 10, 1), fields.starts_on
    assert_equal true, fields.listed
  end

  test "blank strings cast to nil for every scalar type" do
    fields = ContentModel::FieldSet.for(@definition).new({ "venue" => "Hall", "seats" => "", "starts_on" => "", "website" => "", "kind" => "" })
    assert_nil fields.seats
    assert_nil fields.starts_on
    assert_nil fields.website
    assert_nil fields.kind
    assert fields.valid?
    assert_equal({ "venue" => "Hall", "listed" => true }, fields.untranslated_hash)
  end

  test "required, min, select, date and url errors are keyed by field" do
    fields = ContentModel::FieldSet.for(@definition).new({ "seats" => "0", "starts_on" => "not a date", "website" => "javascript:alert(1)", "kind" => "party" })
    assert_not fields.valid?
    %w[venue seats starts_on website kind].each { |key| assert fields.errors[key].any?, "expected an error on #{key}" }
  end

  test "translated field reads fall back publicly and stay literal otherwise" do
    site_settings(:default).update!(default_locale: "de")
    translations = { "de" => { "headline" => "Hallo" } }
    literal = ContentModel::FieldSet.for(@definition).new({ "venue" => "Hall" }, translations, locale: "en")
    public_read = ContentModel::FieldSet.for(@definition).new({ "venue" => "Hall" }, translations, locale: "en", fallback: true)
    assert_nil literal.headline
    assert_equal "Hallo", public_read.headline
  end

  test "components: nested validation with path keys and whole-component translation" do
    fields = ContentModel::FieldSet.for(@with_components).new(
      { "speakers" => [ { "name" => "Ada" }, { "name" => "" } ] },
      { "en" => { "lead" => { "name" => "Grace" } } }, locale: "en")
    assert_not fields.valid?
    assert fields.errors["speakers.1.name"].any?
    assert_equal "Ada", fields.component(:speakers).first.name
    assert_equal "Grace", fields.component(:lead).name
    assert_equal({ "lead" => { "name" => "Grace" } }, fields.translated_hash)
  end

  test "assign writes translated keys for the instance locale only" do
    fields = ContentModel::FieldSet.for(@definition).new({}, {}, locale: "de")
    fields.assign("venue" => "Saal", "headline" => "Hallo")
    assert_equal({ "venue" => "Saal" }, fields.untranslated_hash.slice("venue"))
    assert_equal({ "headline" => "Hallo" }, fields.translated_hash)
  end
end
```

The `teardown` in ContentModel::FieldSetTest restores the real registrations. Task 2 adds them; until then `prepare!` just runs the to_prepare hooks. If `Rails.application.reloader.prepare!` isn't the right call on this Rails version, use whatever re-runs `to_prepare` blocks (check `ActiveSupport::Reloader`) and note it in the report.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/models/type_registry_test.rb test/models/field_set_test.rb`
Expected: FAIL (`uninitialized constant BlockTypes`).

- [ ] **Step 3: Implement**

`app/models/type_registry.rb`:

```ruby
# The shared shape of BlockTypes, ContentTypes and FieldGroups (open-types spec
# §3.2): a name => definition map filled from code at boot (and, later, by
# plugins through the same calls). Reset at the start of every `to_prepare`
# run (config/initializers/types.rb) so a code reload in development
# re-registers cleanly instead of keeping definitions that point at stale,
# unloaded classes.
module ContentModel::Registry
  class UnknownType < KeyError; end

  def register(name, &block)
    definition = definition_class.new(name.to_s)
    block&.call(definition)
    definition.finalize!
    registry[definition.name] = definition
  end

  def fetch(name)
    registry.fetch(name.to_s) { raise UnknownType, "#{name.inspect} isn't a registered #{kind_label}" }
  end

  def find(name)
    registry[name.to_s]
  end

  def names = registry.keys
  def all = registry.values
  def reset! = @registry = {}

  # For tests restoring a definition exactly as it was.
  def registry_put(definition)
    registry[definition.name] = definition
  end

  private

  def registry = (@registry ||= {})
end
```

`app/models/block_types.rb`:

```ruby
module BlockTypes
  extend ContentModel::Registry

  def self.definition_class = ContentModel::BlockContentModel::Definition
  def self.kind_label = "block type"

  def self.with_capability(capability)
    all.select { |definition| definition.capability?(capability) }
  end
end
```

`ContentTypes` has the same shape (`ContentModel::ContentContentModel::Definition`, `"content type"`, plus `def self.default = all.first`). `FieldGroups` also has the same shape (`ContentModel::FieldGroupDefinition`, `"component"`). The `definition_class` / `kind_label` singleton methods are called from `ContentModel::Registry` as `self.class`-free module methods: inside `register`, `definition_class` resolves on the extended module.

`app/models/type_definition.rb`:

```ruby
# One registered type (spec §3.1): its label, its declarative field schema,
# which existing columns it edits, and what it's capable of. The schema is
# data, not a class, so admin-defined types (roadmap Phase 3) can feed the
# same format later; ContentModel::FieldSet turns it into an ActiveModel class.
class ContentModel::Definition
  SCALAR_TYPES = %i[string text integer boolean date url select content_type tag].freeze
  GROUP_TYPES = %i[component components].freeze
  OPTIONS = %i[required default min max translated options of].freeze

  Field = Data.define(:name, :type, :options) do
    def translated? = options[:translated] == true
    def required? = options[:required] == true
    def group? = GROUP_TYPES.include?(type)
  end

  attr_reader :name, :fields, :uses_columns

  def initialize(name)
    @name = name
    @label = name.humanize
    @fields = []
    @uses_columns = []
    @capabilities = []
  end

  def label(value = nil)
    value.nil? ? @label : (@label = value)
  end

  def field(name, type, **options)
    raise ArgumentError, "unknown field type #{type.inspect}" unless (SCALAR_TYPES + GROUP_TYPES).include?(type)
    raise ArgumentError, "unknown field option(s) #{(options.keys - OPTIONS).inspect}" if (options.keys - OPTIONS).any?
    raise ArgumentError, "#{type} fields need `of:` naming a component" if GROUP_TYPES.include?(type) && options[:of].blank?
    raise ArgumentError, "select fields need `options:`" if type == :select && options[:options].blank?

    @fields << Field.new(name: name.to_s, type:, options:)
  end

  def uses(*columns) = @uses_columns.concat(columns.map(&:to_s))
  def capability(*names) = @capabilities.concat(names)
  def capability?(name) = @capabilities.include?(name)

  def field_set = ContentModel::FieldSet.for(self)

  # Hook for subclasses to check the finished definition at registration.
  def finalize!; end
end
```

`ContentModel::FieldGroupDefinition < ContentModel::Definition`:
- `finalize!` raises `ArgumentError, "components can't contain other components (one level only)"` if any field is a group;
- adds `component(klass)` / `#component` (reader when called without an argument, as with `label`).

`ContentModel::BlockContentModel::Definition < ContentModel::Definition` adds `component(klass)` with the same reader/writer pattern.

`ContentModel::ContentContentModel::Definition < ContentModel::Definition` adds `color`, `list_component`, `detail_component` (reader/writer pattern) and `starter(section:, sample:)` / `#starter_data`.

`app/models/field_set.rb`:

```ruby
# Builds, once per definition, the ActiveModel class that casts, validates and
# serializes a type's field values (spec §3.4). Instances wrap the two jsonb
# halves a record stores: `values` (untranslated keys) and `translations`
# ({ locale => { key => value } }) -- read for `locale:`, literally unless
# `fallback: true`, which walks Locales.fallback_chain like Locales.read.
class ContentModel::FieldSet
  URL_SCHEMES = %w[http https mailto].freeze

  def self.for(definition)
    cache[definition] ||= build(definition)
  end

  def self.cache = (@cache ||= {}.compare_by_identity)

  def self.build(definition)
    Class.new(Base) do
      self.definition = definition
      definition.fields.each { |field| define_field(field) }
    end
  end

  class Base
    include ActiveModel::Validations

    class_attribute :definition

    def self.model_name = ActiveModel::Name.new(self, nil, "Fields")

    # Readers return the value cast for the field's type; groups return nested
    # instances via #component.
    def self.define_field(field)
      define_method(field.name) { read(field) }
    end

    attr_reader :locale

    def initialize(values = {}, translations = {}, locale: nil, fallback: false)
      @values = values.to_h.stringify_keys
      @translations = translations.to_h.transform_values { |hash| hash.to_h.stringify_keys }
      @locale = (locale || I18n.locale).to_s
      @fallback = fallback
    end

    validate :validate_fields

    def assign(hash)
      hash.to_h.stringify_keys.each do |key, raw|
        field = definition.fields.find { |f| f.name == key } or next
        value = serialize(field, raw)
        target = field.translated? ? (@translations[@locale] ||= {}) : @values
        value.nil? ? target.delete(key) : target[key] = value
      end
      self
    end

    def untranslated_hash
      definition.fields.reject(&:translated?).each_with_object({}) do |field, hash|
        value = field.group? ? @values[field.name] : serialize(field, @values.fetch(field.name, field.options[:default]))
        hash[field.name] = value unless value.nil?
      end
    end

    # The translations for this instance's locale only (what a save writes).
    def translated_hash
      @translations.fetch(@locale, {}).slice(*definition.fields.select(&:translated?).map(&:name))
    end

    def all_translations = @translations

    def component(name)
      field = definition.fields.find { |f| f.name == name.to_s }
      raw = raw_value(field)
      klass = FieldGroups.fetch(field.options[:of]).field_set
      if field.type == :components
        Array(raw).map { |item| klass.new(item, {}, locale: @locale) }
      else
        raw && klass.new(raw, {}, locale: @locale)
      end
    end

    private

    def read(field)
      return component(field.name) if field.group?

      cast(field, raw_value(field))
    end

    def raw_value(field)
      return @values.fetch(field.name, field.options[:default]) unless field.translated?

      locales = @fallback ? Locales.fallback_chain(@locale) : [ @locale ]
      locales.each do |code|
        value = @translations.dig(code, field.name)
        return value if value.present?
      end
      nil
    end

    def cast(field, value)
      value = nil if value.respond_to?(:blank?) && value.blank? && value != false
      return nil if value.nil?

      case field.type
      when :integer then Integer(value.to_s, exception: false)
      when :boolean then ActiveModel::Type::Boolean.new.cast(value)
      when :date then value.is_a?(Date) ? value : Date.iso8601(value.to_s) rescue nil
      else value.to_s.strip.presence
      end
    end

    # What gets stored: JSON-ready, blanks dropped.
    def serialize(field, raw)
      return raw.presence if field.group?

      value = cast(field, raw)
      value.is_a?(Date) ? value.iso8601 : value
    end

    def validate_fields
      definition.fields.each do |field|
        raw = raw_value(field)
        if field.group?
          validate_group(field)
          next
        end

        value = cast(field, raw)
        errors.add(field.name, :blank) if field.required? && value.nil?
        next if value.nil?

        errors.add(field.name, :invalid) if raw.present? && field.type == :date && !value.is_a?(Date)
        errors.add(field.name, :not_a_number) if raw.present? && field.type == :integer && value.nil?
        errors.add(field.name, :greater_than_or_equal_to, count: field.options[:min]) if field.options[:min] && value.is_a?(Integer) && value < field.options[:min]
        errors.add(field.name, :less_than_or_equal_to, count: field.options[:max]) if field.options[:max] && value.is_a?(Integer) && value > field.options[:max]
        errors.add(field.name, :inclusion) if field.type == :select && !Array(field.options[:options].is_a?(Hash) ? field.options[:options].keys : field.options[:options]).include?(value)
        errors.add(field.name, :inclusion) if field.type == :content_type && ContentTypes.find(value).nil?
        errors.add(field.name, :invalid) if field.type == :url && !url?(value)
      end
    end

    def validate_group(field)
      items = field.type == :components ? Array(component(field.name)).each_with_index.to_a : [ [ component(field.name), nil ] ]
      errors.add(field.name, :blank) if field.required? && items.all? { |item, _| item.nil? }
      items.each do |item, index|
        next if item.nil? || item.valid?

        prefix = index.nil? ? field.name : "#{field.name}.#{index}"
        item.errors.each { |error| errors.add("#{prefix}.#{error.attribute}", error.type, message: error.message) }
      end
    end

    def url?(value)
      URL_SCHEMES.include?(URI.parse(value).scheme.to_s.downcase)
    rescue URI::InvalidURIError
      false
    end
  end
end
```

Treat the code above as a close sketch, not literal transcription. Adjust it until the tests pass, and keep the public interface exactly as listed under **Interfaces**. Two things need particular care:
- `cast` for dates must turn an invalid string into an error, never an exception.
- The cast value, not the raw input, decides "blank".

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/models/type_registry_test.rb test/models/field_set_test.rb`, then `PARALLEL_WORKERS=1 bin/rails test`
Expected: PASS. Nothing else uses the registries yet.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add type registries and declarative field sets"
```

---

### Task 2: String types, polymorphic block owner, built-in definitions, back-end consumers

Spec: §3.1, §4, §6 (back-end rows), §7.

**Files:**
- Create:
  - `db/migrate/20260928090000_open_content_types.rb`
  - `config/initializers/types.rb`
  - `app/models/block_types/rich_text.rb`, `image.rb`, `post_list.rb`
  - `app/models/content_types/blog.rb`, `resume_entry.rb`, `now_update.rb`
  - `test/models/built_in_types_test.rb`
- Modify:
  - `app/models/content_block.rb`, `app/models/page.rb`, `app/models/post.rb`
  - `app/models/public_site/paths.rb`, `app/models/public_site/resolver.rb`
  - `app/controllers/concerns/public_page_rendering.rb`
  - `app/services/content_blocks/save.rb`, `app/services/posts/save.rb`, `app/services/pages/save.rb` (only if it touches blocks)
  - `app/models/starter_content.rb`, `db/seeds.rb`
  - `app/helpers/theme_helper.rb` (`resume_period`)
  - `app/views/content_blocks/post_list/_resume.html.erb` (read `post.fields`)
  - tests that reference `page_id`, integer enums, `Post::ROLE_TYPES`, `post.company`/`role_type`/`start_date`/`end_date`, `ContentBlock.post_list`, `ContentBlock.block_types`, `Post.content_types`

**Interfaces:**
- **Consumes:** Task 1 registries and `ContentModel::FieldSet`.
- **Produces:**
  - **`ContentBlock`:**
    - `belongs_to :owner, polymorphic: true`;
    - `#definition` (the `ContentModel::BlockContentModel::Definition` or nil);
    - `#settings_object(locale: I18n.locale, fallback: false)`;
    - `#assign_settings(hash, locale:)`;
    - `#listed_posts(include_unpublished: false)` and `#lists?(post)`, both delegating to the definition's `lists_posts` behaviour;
    - scope `ContentBlock.listing`, the blocks whose type has `:lists_posts`.
  - **`Page`:** `has_many :content_blocks, as: :owner`.
  - **`Post`:**
    - `#definition`;
    - `#fields(locale: I18n.locale, fallback: false)`;
    - `#assign_fields(hash, locale:)`.
  - **`ResumeEntry`** (constant namespace for the built-in): `ContentContentModel::ResumeEntry::ROLE_TYPES`.
  - **Services** accept `attributes: { settings: {...} }` / `attributes: { fields: {...} }` for untranslated values, and `translations: { locale => { settings: {...} } }` / `{ fields: {...} }` for translated ones.

- [ ] **Step 1: Write the failing tests**

`test/models/built_in_types_test.rb`:

```ruby
require "test_helper"

class BuiltInTypesTest < ActiveSupport::TestCase
  test "built-ins are registered" do
    assert_equal %w[rich_text image post_list], BlockTypes.names
    assert_equal %w[blog resume_entry now_update], ContentTypes.names
    assert BlockTypes.fetch(:post_list).capability?(:lists_posts)
    assert_equal %w[image caption alt], BlockTypes.fetch(:image).uses_columns
  end

  test "post_list settings are typed" do
    block = root_page.content_blocks.build(block_type: "post_list", position: 0)
    block.assign_settings({ "content_type" => "nope", "limit" => "0" }, locale: "en")
    assert_not block.valid?
    assert block.errors["settings.content_type"].any?
    assert block.errors["settings.limit"].any?
  end

  test "resume fields live on the resume_entry type" do
    post = Post.new(content_type: "resume_entry", title: "Engineer")
    post.assign_fields({ "company" => "Acme", "role_type" => "lead", "start_date" => "2023-01-01", "end_date" => "" }, locale: "en")
    assert post.valid?, post.errors.full_messages.to_sentence
    assert_equal "Acme", post.fields.company
    assert_nil post.fields.end_date
    assert_not Post.new(content_type: "blog").respond_to?(:company)
  end

  test "an unregistered stored type is invalid on save" do
    assert_not Post.new(content_type: "gallery", title: "X").valid?
    block = root_page.content_blocks.build(block_type: "gallery", position: 0)
    assert_not block.valid?
    assert_includes block.errors[:block_type], "isn't a registered block type"
  end

  test "an unregistered stored block type is skipped on render and sync" do
    page = create_page(title: "About")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    block.update_column(:block_type, "gallery")
    post = create_post(title: "Hello")
    post.update_column(:content_type, "gallery")

    assert_nothing_raised { PublicSite::Paths.sync(post) }
    assert_nil post.reload.full_path("en")
    assert_nil block.reload.definition
    assert_empty page.content_blocks.listing
  end
end
```

The render half of "skipped on render" is pinned in Task 4, where rendering moves to components. Here it's the model and sync half.

Also update the existing tests that break because of `page_id` → `owner`, string types and resume accessors. List each one in your report.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/models/built_in_types_test.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

Migration `db/migrate/20260928090000_open_content_types.rb`. Greenfield: this rewrites the columns outright. Existing dev data is dropped with `db:reset` afterwards.

```ruby
class OpenContentTypes < ActiveRecord::Migration[8.1]
  def up
    remove_reference :content_blocks, :page, index: true, foreign_key: true
    add_reference :content_blocks, :owner, polymorphic: true, null: false, index: false
    add_index :content_blocks, [ :owner_type, :owner_id, :position ]
    change_column :content_blocks, :block_type, :string, null: false, default: nil, using: "block_type::text"
    add_column :content_blocks, :translated_settings, :jsonb, null: false, default: {}

    change_column :posts, :content_type, :string, null: false, default: nil, using: "content_type::text"
    add_index :posts, :content_type
    add_column :posts, :translated_metadata, :jsonb, null: false, default: {}
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

Check the real current columns in `db/schema.rb` first: the foreign key and index names on `content_blocks.page_id`, and whether `block_type`/`content_type` have defaults. Adjust the calls to match. The `using:` cast turns integers into `"0"`/`"1"`; that's fine because `db:reset` follows. Run `bin/rails db:migrate` and commit `db/schema.rb`.

`config/initializers/types.rb`:

```ruby
# Built-in block types, content types and field groups (open-types spec §3.1),
# registered through the same calls plugins will use. Inside `to_prepare` so
# a code reload in development re-registers against the freshly loaded
# classes; the registries are reset first, so nothing is registered twice.
Rails.application.config.to_prepare do
  [ BlockTypes, ContentTypes, FieldGroups ].each(&:reset!)

  BlockContentModel::RichText.register
  BlockContentModel::Image.register
  BlockContentModel::PostList.register

  ContentContentModel::Blog.register
  ContentContentModel::ResumeEntry.register
  ContentContentModel::NowUpdate.register
end
```

Each built-in lives in its own file with a `self.register` class method. Registration order matters: it defines `names` order and `ContentTypes.default` (blog).

- `app/models/block_types/post_list.rb`:

```ruby
module BlockTypes
  # A listing of posts (spec §3.1, §6): which posts it lists is its settings'
  # content type (blank = every type) and tag; `limit` trims display only.
  # Carries the `lists_posts` capability, which is what canonical URLs and the
  # resolver's listing fallback look for.
  module PostList
    def self.register
      BlockTypes.register :post_list do |t|
        t.label "Post list"
        t.field :content_type, :content_type
        t.field :tag, :string
        t.field :limit, :integer, min: 1
        t.capability :lists_posts
      end
    end

    # The body of today's ContentBlock#listed_posts, taking the block's cast
    # settings -- moved here verbatim with its comments.
    def self.listed_posts(settings, include_unpublished: false) = …

    # The body of today's ContentBlock#lists?, likewise.
    def self.lists?(settings, post) = …
  end
end
```

  Move the two method bodies over verbatim, including their comments, reading `settings.content_type` / `settings.tag`. The `component` line is added in Task 4.
- `rich_text.rb`: `t.uses :body`.
- `image.rb`: `t.uses :image, :caption, :alt`.
- `content_types/blog.rb`: label "Blog", colour `"#3b82f6"`, starter section `{ title: "Blog", slug: "blog" }` and the sample post from today's `StarterContent::SECTIONS`.
- `content_types/resume_entry.rb`:
  - holds `ROLE_TYPES` (moved from `Post`);
  - fields `company :string`, `role :string`, `role_type :select, options: ROLE_TYPES`, `start_date :date`, `end_date :date`;
  - colour `"#10b981"`; starter from `SECTIONS`, with the sample's `metadata` becoming `fields`.
- `content_types/now_update.rb`: colour `"#f59e0b"`, starter from `SECTIONS`.

`ContentBlock` changes:
- `belongs_to :owner, polymorphic: true`;
- delete the `enum` and its comment about sharing a name with `image` (Active Storage's `#image` stays);
- `validate :block_type_is_registered`, which adds `errors.add(:block_type, "isn't a registered block type")` when `BlockTypes.find(block_type)` is nil;
- `validate :settings_are_valid`, which copies the settings object's errors under `settings.<path>`;
- delete `discard_blank_settings` and `post_list_settings_reference_a_real_content_type`.

```ruby
def definition = BlockTypes.find(block_type)

def settings_object(locale: I18n.locale, fallback: false)
  definition&.field_set&.new(settings, translated_settings, locale:, fallback:)
end

def assign_settings(hash, locale:)
  object = settings_object(locale:) or return
  object.assign(hash)
  self.settings = object.untranslated_hash
  self.translated_settings = object.all_translations.merge(locale.to_s => object.translated_hash).compact_blank
end

scope :listing, -> { where(block_type: BlockTypes.with_capability(:lists_posts).map(&:name)) }

def listed_posts(include_unpublished: false)
  return Post.none unless definition&.capability?(:lists_posts)

  BlockContentModel::PostList.listed_posts(settings_object, include_unpublished:)
end

def lists?(post)
  definition&.capability?(:lists_posts) ? BlockContentModel::PostList.lists?(settings_object, post) : false
end
```

`listed_posts`/`lists?` delegate to `BlockContentModel::PostList` directly. With a single listing type this is fine; comment that a second listing type would move the behaviour onto the definition (`t.lists_posts_with …`). `sync_listed_post_paths` keeps working, but reads `definition&.capability?(:lists_posts)` and `settings_object&.content_type` instead of `post_list?` / `settings["content_type"]`. For the "before last save" half, read `settings_before_last_save["content_type"]` and `block_type_before_last_save`, checking the old type through `BlockTypes.find(...)&.capability?(:lists_posts)`.

`Page`:
- `has_many :content_blocks, -> { order(:position) }, as: :owner, dependent: :destroy`;
- `accepts_nested_attributes_for` stays (Avo);
- in `resync_listed_posts`, use `ContentBlock.listing.where(owner: self_and_descendants)` and `settings_object.content_type`.

`Post`:
- delete the `enum` (keep `validates :content_type, presence: true`);
- add `validate :content_type_is_registered` ("isn't a registered content type"), `validate :fields_are_valid` (errors under `fields.<path>`), `#definition`, `#fields(locale:, fallback:)` and `#assign_fields(hash, locale:)`, mirroring the `ContentBlock` methods over `metadata`/`translated_metadata`;
- delete `ROLE_TYPES`, the `store_accessor` and the `role_type` inclusion validation; the field schema covers them now.
- Keep the `LocalizedSlug scope: :content_type` (string now; works unchanged).

`PublicSite::Paths`:
- `canonical_page` uses `ContentBlock.listing.includes(:owner)` and `block.owner` (only `Page` owners count: `select { |b| b.owner.is_a?(Page) }`).
- The specificity ranking reads `block.settings_object.content_type` / `.tag`.
- `sync`/`compute` skip a post whose `definition` is nil and write no paths for it (log `Rails.logger.warn`).
- `sync_posts(content_type)` keeps its signature.

Other call sites:
- `PublicSite::Resolver#listing_fallback`: `page_row.record.content_blocks.listing`.
- `PublicPageRendering#assign_record`: `@page.content_blocks.listing.find { |b| b.lists?(record) }`.
- **Services:**
  - `ContentBlocks::Save` assigns `attributes[:settings]` through `assign_settings(…, locale: Locales.default)` and `translations[locale][:settings]` through `assign_settings(…, locale:)`; `block_type` is a string; the position default reads `@block.owner.content_blocks`.
  - `Posts::Save` does the same with `fields` (`assign_fields`). Its failure `Result` carries the per-field errors (they are already on `record.errors`).
- `StarterContent` builds its sections from `ContentTypes.all.filter_map(&:starter_data)`. The rules stay the same:
  - idempotent;
  - lookups across enabled locales;
  - failures raise.
  The sample post's typed values go through `Posts::Save` `attributes: { fields: … }`.
- `db/seeds.rb`: string types, typed fields via the services.
- `ThemeHelper#resume_period(post)` reads `post.fields.start_date` / `end_date`. They are now `Date` or nil: use `.year`.
- `_resume.html.erb` reads `post.fields.company` and `ContentContentModel::ResumeEntry::ROLE_TYPES[post.fields.role_type]`. It's replaced by a component in Task 4; this keeps it working until then.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails db:migrate && bin/rails test test/models/built_in_types_test.rb`, then `PARALLEL_WORKERS=1 bin/rails test`, `bin/rails test test/system` (alone), `bin/rails db:reset` (dev) and `bin/rails runner 'puts PublicPath.current.where(record_type: "Post").pluck(:path).inspect'`.
Expected: PASS. Seeded posts still sit under their section pages.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: string content and block types backed by registries"
```

---

### Task 3: MCP, Avo and the mind graph read the registries

Spec: §6 (MCP, Avo, mind graph rows).

**Files:**
- Modify:
  - `app/mcp/mcp/tools/create_post.rb`, `app/mcp/mcp/tools/list_posts.rb`, `app/mcp/mcp/tools/update_post.rb`, `app/mcp/mcp/post_serializer.rb`
  - `app/avo/filters/content_type.rb`, `app/avo/resources/post.rb`, `app/avo/resources/content_block.rb`, `app/avo/resources/page.rb`
  - `app/avo/resource_tools/nested_content_blocks.rb`, `app/views/avo/partials/_content_block_row.html.erb`
  - `app/controllers/avo/tools_controller.rb`, the mind-graph view that mounts `mind_graph_controller.js`, `app/javascript/controllers/mind_graph_controller.js`
- Create: `app/views/avo/partials/_typed_fields.html.erb` (generic schema-driven inputs; throwaway until the admin)
- Test:
  - `test/mcp/tools/*`, `test/mcp/post_serializer_test.rb`
  - `test/integration/avo_page_editing_test.rb`, `test/integration/avo_post_translations_test.rb` (or the Avo post test that edits resume fields)
  - `test/integration/mind_graph_test.rb`

**Interfaces:**
- **Consumes:** `ContentTypes.names/all`, `BlockTypes.all`, `definition.fields`, `definition.color`, `post.fields`, `post.assign_fields`, `block.settings_object`, `block.assign_settings`.
- **Produces:**
  - MCP tool schemas with `content_type` enum = `ContentTypes.names`. They are built lazily: override the tool's input-schema reader, or rebuild the schema after boot. Check how the `mcp` gem stores `input_schema`, so an enum captured at class load doesn't freeze an empty registry.
  - `Mcp::PostSerializer` emits `fields` (untranslated keys plus the requested locale's translated keys, literal) instead of `metadata`.
  - `CreatePost`/`UpdatePost` accept an optional `fields` object, validated through `Posts::Save`. Errors come back keyed per field.

- [ ] **Step 1: Write the failing tests**

- **MCP.**
  - `tools/list` shows the `create_post_tool` `content_type` enum as `%w[blog resume_entry now_update]`, and it includes a type registered inside the test. Register it and then list, which proves the schema isn't frozen at load.
  - `create_post_tool` with `content_type: "resume_entry", fields: { company: "Acme", role_type: "lead", start_date: "2023-01-01" }` creates the post, and `get_post_tool` returns `fields: { "company" => "Acme", "role_type" => "lead", "start_date" => "2023-01-01" }` with no `metadata` key.
  - `fields: { role_type: "boss" }` returns an MCP error naming `fields.role_type`.
- **Avo.**
  - Editing a post of type `resume_entry` in Avo saves `company` through the typed inputs.
  - A page form's post_list block row saves `settings[limit]` = "3" as the integer 3, and a blank `limit` as absent.
- **Mind graph.** The JSON / data the mind graph receives carries each post's type colour from the registry (`"#10b981"` for `resume_entry`).

Write these in each file's existing style.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/mcp test/integration/mind_graph_test.rb test/integration/avo_page_editing_test.rb`
Expected: FAIL.

- [ ] **Step 3: Implement**

- **MCP tools.**
  - The `content_type` enum comes from `ContentTypes.names` at schema-read time.
  - Add a `fields` object property (`type: "object"`, described as the type's typed fields) to create and update.
  - Pass it to `Posts::Save` as `attributes: { fields: … }`, plus `translations: { locale => { fields: … } }` for translated keys. Split them by `post.definition.fields.select(&:translated?)`.
  - `list_posts` filters by string type unchanged.
- **Serializer.** `fields: post.fields(locale:).untranslated_hash.merge(post.fields(locale:).translated_hash)`. Drop `metadata`. Update the serializer comment.
- **Avo.**
  - The filter options come from `ContentTypes.all.to_h { |d| [d.label, d.name] }`.
  - The post resource's `content_type` field becomes a select with options from the registry.
  - Add one field per content-type field. The simplest Avo-compatible approach is a `:text` field per field name, with `visible: ->(resource:) { resource.record.definition&.fields&.any? { |f| f.name == name } }` and getters/setters going through `post.fields` / `post.assign_fields`. Check what Avo 4 Community supports: `as: :text` with `format_using` / `update_using`.
  - Content block resource and nested row: `block_type` options from `BlockTypes.all`. The settings inputs are rendered by `_typed_fields.html.erb` from `block.definition.fields` (text inputs for scalars, a select for `select`/`content_type`). Component fields aren't editable in Avo; show "edited in the new admin".
  - `extra_params` in `app/avo/resources/page.rb` stays built from `Locales::SUPPORTED.keys`, with `settings: {}` kept.
- **Mind graph.** `tools_controller#mind_graph` adds `color: post.definition&.color` per node. `mind_graph_controller.js` uses `node.color` (fallback `#9ca3af`) instead of its hard-coded map.

- [ ] **Step 4: Run the tests to verify they pass**

Run: the step-2 files, then `PARALLEL_WORKERS=1 bin/rails test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: drive MCP, Avo and the mind graph from the type registries"
```

---

### Task 4: ViewComponent rendering (+ Lookbook)

Spec: §5, §6 (rendering rows).

**Files:**
- Modify:
  - `Gemfile`, `Gemfile.lock`
  - `config/routes.rb` (Lookbook, development only)
  - `app/assets/tailwind/themes/default/theme.css` (`@source` the components)
  - `app/views/pages/show.html.erb`
  - the built-in definition files (add `component` / `list_component` / `detail_component`)
- Create:
  - `app/components/blocks/rich_text_component.rb` + `.html.erb`
  - `app/components/blocks/image_component.rb` + `.html.erb`
  - `app/components/blocks/post_list_component.rb` + `.html.erb`
  - `app/components/posts/blog_list_component.rb` + `.html.erb`
  - `app/components/posts/resume_list_component.rb` + `.html.erb`
  - `app/components/posts/now_list_component.rb` + `.html.erb`
  - `app/components/posts/detail_component.rb` + `.html.erb`
  - `app/components/fields/group_component.rb` + `.html.erb`
  - `app/components/application_component.rb`
  - `app/models/theme.rb` (`Theme.current.component_for(definition)` lookup hook)
  - `test/components/previews/**` (Lookbook previews)
  - `test/components/*_test.rb`
- Delete:
  - `app/views/content_blocks/_rich_text.html.erb`, `_image.html.erb`, `_post_list.html.erb`, `_post_list_detail.html.erb`
  - `app/views/content_blocks/post_list/*`

**Interfaces:**
- **Consumes:** definitions (Task 2), `ThemeHelper` helpers (`translated`, `post_date`, `resume_period`, `post_url_path` via `helpers.`).
- **Produces:**
  - **`ContentModel::BlockContentModel::Definition#component`:** a component class with `initialize(block:, page:)`.
  - **`ContentModel::ContentContentModel::Definition#list_component`:** a class with `initialize(posts:, page:)`, rendering a whole list.

    Note: the spec says `list_item_component`. The plan uses a whole-list component because the `now` listing shows only the latest post. It's recorded as a ruling in the ledger, and a list component still renders its items through its own template.
  - **`ContentModel::ContentContentModel::Definition#detail_component`:** `initialize(post:)`.
  - **`ContentModel::FieldGroupDefinition#component`:** `initialize(value:)` (a `ContentModel::FieldSet` instance).
  - **`ContentTypes.default.list_component`:** used for a list with a blank `content_type`.
  - **`Theme.current.component_for(definition, role = :component)`:** returns the definition's class for now (the default theme). This is the hook alternate themes will override.

- [ ] **Step 1: Write the failing tests**

- **`test/components/blocks/post_list_component_test.rb`** (uses `ViewComponent::TestHelpers`):
  - a blog list renders titles linked to their canonical URLs;
  - `limit` trims the list;
  - `test "an unfiltered post list renders every type with the default rows"`: blank `content_type`, a blog post and a resume entry, both titles rendered through the blog list component.
- **`test/components/posts/resume_list_component_test.rb`:** the period ("2023 – now"), company and role-type label render.
- **`test/components/blocks/image_component_test.rb`:** alt and caption fall back along the fallback chain.
- **`test/integration/public_blocks_test.rb`** (existing): must stay green unchanged. It is the regression net for the port. Add `test "an unregistered stored block type is skipped on render"`: a page with a rich_text block and a block whose `block_type` was set to `"gallery"` via `update_column` → GET 200, the rich text renders, and nothing for the gallery block.
- **`test/components/previews_test.rb`:** iterate over every Lookbook preview class and render each example, asserting no exception. Use `ViewComponent::Preview.all`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/components test/integration/public_blocks_test.rb`
Expected: FAIL (no components).

- [ ] **Step 3: Implement**

1. **Gems.** `bundle add view_component`, then `bundle add lookbook --group "development,test"`. If `bundle` can't reach rubygems (sandbox), stop and report BLOCKED; don't vendor gems by hand.
2. **Lookbook** is mounted in `config/routes.rb` inside `if Rails.env.development?`, declared before the catch-alls, with a comment saying it's dev-only. `config.view_component.previews.paths` / Lookbook's preview paths point at `test/components/previews`.
3. **`ApplicationComponent < ViewComponent::Base`** with `delegate :translated, :post_date, :resume_period, :post_url_path, :page_url_path, to: :helpers`.
4. **Port each partial to its component verbatim** (same markup, classes and comments), replacing locals with explicit inputs:
   - `Blocks::RichTextComponent(block:, page:)`
   - `Blocks::ImageComponent(block:, page:)`
   - `Blocks::PostListComponent(block:, page:)`. It computes `posts = block.listed_posts.order(published_at: :desc).includes(:tags)`, applies `settings_object.limit`, then renders `Theme.current.component_for(list_definition, :list_component).new(posts:, page:)`, where `list_definition = ContentTypes.find(settings_object.content_type) || ContentTypes.default`.
   - `Posts::BlogListComponent`, `Posts::ResumeListComponent`, `Posts::NowListComponent` (`posts:, page:`)
   - `Posts::DetailComponent(post:)`
   - `Fields::GroupComponent(value:)`: renders a field group generically as a definition list of label → value. No built-in uses it yet; it's exercised by the Task 5 test type and a preview.
5. **Definitions:**
   - `BlockContentModel::RichText` / `Image` / `PostList` get `t.component Blocks::…Component`;
   - `ContentContentModel::Blog` gets `t.list_component Posts::BlogListComponent` and `t.detail_component Posts::DetailComponent`; the same pattern applies for resume and now (both use `Posts::DetailComponent` for detail).
6. **`pages/show.html.erb`.** The block loop becomes:

```erb
<% @page.content_blocks.each do |block| %>
  <% if @post && block == @post_list_block %>
    <% definition = @post.definition %>
    <%= render Theme.current.component_for(definition, :detail_component).new(post: @post) if definition %>
  <% elsif (definition = block.definition) %>
    <%= render Theme.current.component_for(definition).new(block: block, page: @page) %>
  <% else %>
    <% Rails.logger.warn("Skipping block #{block.id}: unregistered block type #{block.block_type.inspect}") %>
  <% end %>
<% end %>
```

   Keep the existing comment above the loop, updated.
7. **`app/models/theme.rb`:**

```ruby
# The active public theme's component overrides (open-types spec §5). Only
# the lookup exists for now: the default theme uses each definition's own
# component. An alternate theme will map definition names to its own
# component classes here, with the definition's as the fallback.
class Theme
  def self.current = @current ||= new

  def component_for(definition, role = :component)
    definition.public_send(role)
  end
end
```

8. **Tailwind.** Add `@source "../../../../components/blocks";`, `.../posts` and `.../fields` to `app/assets/tailwind/themes/default/theme.css`, and remove the `views/content_blocks` source if that directory is now empty. Rebuild with `bin/rails tailwindcss:build`, and check that the public classes (e.g. `grid-cols-[7rem_1fr_auto]`) are still in `app/assets/builds/theme-default.css`.
9. **Previews** in `test/components/previews/`: one preview class per component with examples for typical states (with and without caption, empty list, a limited list, a resume entry with no end date). Build records in memory (`Post.new(...)`), or with `ActiveRecord::Base.transaction { …; raise ActiveRecord::Rollback }`, so previews never write to the DB.
10. **Delete** the old partials; `grep -rn "content_blocks/" app` must be empty.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/components test/integration/public_blocks_test.rb`, then `PARALLEL_WORKERS=1 bin/rails test`, `bin/rails test test/system` (alone), `bin/rails zeitwerk:check`, and `bin/rails runner 'puts Rails.application.routes.url_helpers.respond_to?(:lookbook_path)'` in development.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: render blocks and post lists through view components"
```

---

### Task 5: Open-type proof with test-only types

Spec: §1 (success), §8 ("open-type proof").

**Files:**
- Create: `test/integration/open_types_test.rb`, `test/support/test_types.rb` (helper that registers and unregisters test-only types)

**Interfaces:**
- **Consumes:** everything above.
- **Produces:** `with_test_types { … }` test helper. It registers:
  - block type `quote` (field `text :string, required: true, translated: true`, field `cite :url`, component `TestQuoteComponent`, defined in the support file with an inline template via `erb_template`);
  - content type `event` (fields `venue :string`, `speakers :groups, of: :speaker`, list and detail components reusing `Posts::BlogListComponent` / `Posts::DetailComponent`);
  - field group `speaker` (`name :string, required: true`).

  It yields, and in `ensure` restores the registries with `Rails.application.reloader.prepare!` (or the call Task 1 settled on).

- [ ] **Step 1: Write the tests**

```ruby
require "test_helper"

class OpenTypesTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  test "a new block type needs no migration and renders through its component" do
    with_test_types do
      page = create_page(title: "Quotes")
      result = ContentBlocks::Save.call(page.content_blocks.build, attributes: { block_type: "quote", settings: { cite: "https://example.org" } },
        translations: { "en" => { settings: { text: "Hello" } } })
      assert result.ok?, result.errors.to_sentence
      get "/quotes"
      assert_response :success
      assert_select "blockquote", /Hello/
    end
  end

  test "a new content type gets canonical URLs, MCP schema entries and typed validation" do
    with_test_types do
      listing = create_page(title: "Events")
      ContentBlocks::Save.call(listing.content_blocks.build, attributes: { block_type: "post_list", settings: { content_type: "event" } })
      ok = Posts::Save.call(attributes: { content_type: "event", published: true, fields: { venue: "Hall", speakers: [ { name: "Ada" } ] } },
        translations: { "en" => { title: "Launch" } })
      assert ok.ok?, ok.errors.to_sentence
      assert_equal "/events/launch", ok.record.full_path("en")

      bad = Posts::Save.call(attributes: { content_type: "event", fields: { speakers: [ { name: "" } ] } }, translations: { "en" => { title: "Bad" } })
      assert_not bad.ok?
      assert bad.errors.any? { |message| message.include?("Speakers.0.name") || message.include?("speakers.0.name") }

      schema = Mcp::Tools::CreatePost.input_schema.to_h
      assert_includes schema.dig(:properties, :content_type, :enum), "event"
    end
  end
end
```

Adjust the MCP schema access to however the tool exposes its schema (Task 3 made it lazy), and adjust the error-message assertion to the real message format; the point is a per-field path. The first test also exercises translated block settings.

- [ ] **Step 2: Run the tests.** `bin/rails test test/integration/open_types_test.rb`. If they fail, fix the production code the failure points at, not the test's intent. List every production change in the report.
- [ ] **Step 3: Full verification.**
  - `PARALLEL_WORKERS=1 bin/rails test`
  - `bin/rails test test/system` (alone)
  - `bin/rubocop`
  - `bin/brakeman -q --no-pager`
  - `bin/bundler-audit`
  - `bin/importmap audit`
  - `bin/rails zeitwerk:check`
  - `bin/rails db:reset`, then check that seeded posts sit under their section pages
  - `grep -rnE "Post\.content_types|ContentBlock\.block_types|ROLE_TYPES" app config lib db/seeds.rb`, which may only show `ContentContentModel::ResumeEntry::ROLE_TYPES`

  Expected: all clean.
- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "test: prove new block and content types need no migration"
```
