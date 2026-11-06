# One block of a type, filled from its definition's sample (block types spec,
# decision 14), so every shared test builds it the same way and a type nobody
# wrote a row for is in every shared test from the day it is registered.
#
# Written through `ContentBlocks::Save`, as an editor's save is: a translated
# schema field goes in its language's `settings`, `caption` and `alt` are the
# columns, `body` is Markdown written in the default language, `image: true`
# attaches a new library image, `form: true` makes a visitor's form (one
# required short text, "Your name") and names it in the block's `:form`
# field (the Form block's `form_id`).
#
# `assert_every_type_built` ends each shared test: it compares the types this
# test built with the registry, in the test and not after the run, because
# the suite runs in parallel workers. It records names, not places: it says
# a test built a block of each type somewhere, which catches a shared test
# that forgot the helper, and not whether the block sat at the top level or
# in a column (the smoke test checks that by what the page draws).
module BlockSamples
  # Every type declares a sample (block types spec, decision 2).
  def sampled_types = BlockTypes.all

  def sample_block(page, type, section: nil)
    definition = BlockTypes.fetch(type)
    sample = definition.sample or flunk("#{definition.name} declares no sample")
    fields = definition.fields.map(&:name)

    default = Locales.default
    # A translated schema field of the default language is saved with the
    # untranslated ones, as the editor's default-language card sends it; in
    # another language it goes in that language's `settings`.
    own_default = sample.translations.fetch(default, {}).transform_keys(&:to_s).slice(*fields)
    attributes = { block_type: definition.name, settings: sample.settings.merge(own_default) }
    attributes.merge!(section_id: section.id, section_column: 1) if section
    attributes[:media_asset_id] = create_media_asset.id if sample.image
    if sample.form
      form_field = definition.fields.find { |field| field.type == :form } or flunk("#{definition.name}'s sample makes a form, and it has no :form field to name it in")
      attributes[:settings] = attributes[:settings].merge(form_field.name => sample_form.id.to_s)
    end

    translations = sample.translations.to_h do |locale, values|
      values = values.transform_keys(&:to_s)
      own = locale == default ? {} : values.slice(*fields)
      [ locale, values.except(*fields).transform_keys(&:to_sym).merge(own.any? ? { settings: own } : {}) ]
    end
    translations[default] = (translations[default] || {}).merge(body: rich_doc(sample.body, tables: definition.body_content == :table)) if sample.body

    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: attributes, translations: translations)
    assert result.ok?, "the sample of #{definition.name} does not save: #{result.errors.to_sentence}"
    (@built_block_types ||= []) << definition.name
    result.record
  end

  # A form for a sample that says `form: true`, written as a row (a test's
  # form, as the fixtures' are): one required short text, which is the word
  # the Form block's sample shows.
  def sample_form
    Forms::Form.create!(name: "Sample form", keep_submissions: false,
      fields: [ { "key" => "f_sample01", "type" => "short_text", "required" => true, "label" => { "en" => "Your name" }, "help" => {}, "settings" => {} } ])
  end

  def sample_every_type(page)
    containers, others = sampled_types.partition { |definition| definition.capability?(:container) }
    others.each { |definition| sample_block(page, definition.name) }
    containers.each do |container|
      section = sample_block(page, container.name)
      others.each { |definition| sample_block(page, definition.name, section: section) }
    end
  end

  # A type's preview (the tile's heading and text) shows something the
  # sample put in: a settings value, a translation's value, or a run of eight
  # characters of the body's plain text.
  def assert_preview_shows_a_sample_value(type)
    definition = BlockTypes.fetch(type)
    sample = definition.sample
    block = sample_block(create_page(title: "Preview #{definition.name}"), definition.name)
    preview = definition.preview.call(block, locale: "en")
    assert_kind_of ContentModel::Preview, preview, "#{definition.name}'s preview is not a ContentModel::Preview"
    shown = [ preview.heading, preview.text ].join(" ")

    values = sample.settings.values + sample.translations.fetch("en", {}).values
    values = values.map(&:to_s).reject(&:blank?)
    plain = sample.body ? RichText::Document.new(rich_doc(sample.body, tables: definition.body_content == :table)).plain_paragraphs.join(" ") : ""
    runs = plain.length >= 8 ? (0..plain.length - 8).map { |i| plain[i, 8] } : []
    assert(values.any? { |value| shown.include?(value) } || runs.any? { |run| shown.include?(run) },
           "#{definition.name}'s preview #{shown.inspect} shows none of its sample's values")
  end

  def assert_every_type_built(names = BlockTypes.names)
    missing = names - Array(@built_block_types).uniq
    assert_empty missing, "this shared test built no block of #{missing.join(", ")}: build every type with sample_block or sample_every_type"
  end
end

# `with_every_type { … }`: every registered type for a block: the built-ins,
# `test/quote` (a type with an owner's name, test/support/test_types.rb) and
# `gallery/album` (an outside type through the plugin hook,
# test/support/gallery_album.rb). `with_gallery_album` goes outside: it
# prepares the registries again, which would drop a type `with_test_types`
# had registered before it. Included by the shared tests that can run the
# test types; the canary and the scaffold build the built-ins alone.
module EveryBlockType
  include TestTypes
  include GalleryAlbum

  def with_every_type(&block) = with_gallery_album { with_test_types(&block) }
end
