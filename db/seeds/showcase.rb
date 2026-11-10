# The development site's showcase (issue #137): pages under `/showcase` that
# draw every registered block type, so a theme's templates and a public
# change are seen where they break: every type at the top level; every type
# in a section of every layout, in each of the three bands, and a band at
# full width; every Note kind, titled and not, on the page and in a strong
# band; a table long and wide enough to scroll; a list of each post type and
# one narrowed to a tag; and a link to an address that is no page, which
# answers the 404 page.
#
# Loaded by `db/seeds.rb` in development only, and by its test
# (`test/models/seeds_test.rb`), which runs it on the test database. Each
# block is built from its type's declared sample through
# `ContentModel::SampleBlock`, as the shared tests build theirs, and written
# through the save services, as an editor's save is; a type a gem registers
# is drawn the day it is registered. The posts the lists show are the seed's
# own (`db/seeds.rb`); the showcase makes none.
#
# IDEMPOTENT. A page is found by its slug under its parent and made when it
# is missing; its blocks are written only while it has none. So a second run
# writes nothing, and a page an editor emptied is filled again, which on a
# development database is what is wanted. Its pages are made published and
# `db/seeds.rb` publishes what was built afterwards (its last step).
module DevelopmentShowcase
  SLUG = "showcase".freeze
  TABLE_ROWS = 40
  FORM_NAME = "Showcase form".freeze
  # The bands a section has, in the order a person reads them.
  BANDS = BlockTypes::Section::BACKGROUNDS

  module_function

  # `root:` the homepage, `image:` a library image every block whose sample
  # shows one draws. Answers the `/showcase` page.
  def call(root:, image:)
    showcase = page(root, SLUG, "Showcase")
    form = sample_form

    top = page(showcase, "every-block", "Every block")
    fill(top) { content_types.each { |definition| sample(top, definition, image:, form:) } }

    BANDS.each do |background|
      band = page(showcase, "band-#{background}", "Band: #{background}")
      fill(band) do
        section_layouts.each { |layout| section(band, layout:, background:, width: "content", image:, form:) }
        section(band, layout: "three", background:, width: "full", image:, form:)
      end
    end

    notes = page(showcase, "every-note", "Every note")
    fill(notes) do
      note_kinds.each do |kind|
        # Untitled in every language: headed by its kind's word.
        sample(notes, BlockTypes.fetch("note"), settings: { "kind" => kind, "title" => "" }, locales: [ Locales.default ])
        sample(notes, BlockTypes.fetch("note"), settings: { "kind" => kind, "title" => "A #{kind} with a title of its own" })
      end
      %w[tinted strong].each do |background|
        band = save(notes, block_type: "section", settings: { "layout" => "two", "background" => background, "width" => "content" })
        note_kinds.each_with_index do |kind, index|
          sample(notes, BlockTypes.fetch("note"), settings: { "kind" => kind }, section: band, column: (index % 2) + 1)
        end
      end
    end

    table = page(showcase, "a-long-table", "A long table")
    fill(table) { save(table, { block_type: "table" }, Locales.default => { caption: "#{TABLE_ROWS} rows, eight columns", body: long_table }) }

    lists = page(showcase, "every-list", "Every list")
    fill(lists) do
      ContentTypes.names.each { |type| save(lists, block_type: "post_list", settings: { "content_type" => type.to_s }) }
      save(lists, block_type: "post_list", settings: { "tag" => "ruby", "limit" => 2 })
    end

    fill(showcase) { save(showcase, { block_type: "rich_text" }, Locales.default => { body: body(intro) }) }
    showcase
  end

  def section_layouts = BlockTypes::Section::LAYOUTS.keys

  def note_kinds = BlockTypes::Note::KINDS.keys

  # Every type that holds content of its own: a container is drawn around
  # them, never inside one.
  def content_types = BlockTypes.all.reject { |definition| definition.capability?(:container) }

  # A section of `layout` holding one block of every content type, dealt
  # over its columns left to right.
  def section(page, layout:, background:, width:, image:, form:)
    band = save(page, block_type: "section", settings: { "layout" => layout, "background" => background, "width" => width })
    columns = BlockTypes::Section.weights(layout).size
    content_types.each_with_index do |definition, index|
      sample(page, definition, image:, form:, section: band, column: (index % columns) + 1)
    end
  end

  def sample(page, definition, image: nil, form: nil, settings: {}, section: nil, column: 1, locales: Locales.enabled)
    attributes, translations = ContentModel::SampleBlock.arguments(definition, default: Locales.default, locales:,
      settings:, section:, column:,
      media_asset_id: (image.id if definition.sample.image), form_id: (form.id if definition.sample.form))
    save(page, attributes, translations)
  end

  def save(page, attributes, translations = {})
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: attributes, translations: translations)
    raise "seeds: #{result.errors.to_sentence}" unless result.ok?

    result.record
  end

  def page(parent, slug, title)
    found = Page.i18n.where(slug: slug).where(parent_id: parent.id).first
    return found if found

    result = Pages::Save.call(attributes: { parent: parent, published_at: Time.current },
      translations: { Locales.default => { title: title, slug: slug } })
    raise "seeds: #{result.errors.to_sentence}" unless result.ok?

    result.record
  end

  def fill(page)
    yield if page.content_blocks.none?
  end

  # The Form block's sample names a form (`form: true`): one required short
  # text, as the shared tests' form, made once through the builder's save.
  # It keeps its submissions for the site's default time, a form needing
  # somewhere to send them, so a test send is read under Forms.
  def sample_form
    Forms::Form.find_by(name: FORM_NAME) || begin
      result = Forms::Save.call(Forms::Form.new, attributes: { name: FORM_NAME, keep_submissions: true },
        fields: [ { key: "", type: "short_text", required: true, label: { Locales.default => "Your name" }, help: {}, settings: {} } ],
        destinations: [])
      raise "seeds: #{result.errors.to_sentence}" unless result.ok?

      result.record
    end
  end

  def long_table
    head = [ "Row", "Plan", "Monthly price", "Storage", "Seats", "Support", "Region", "Notes" ]
    rows = (1..TABLE_ROWS).map do |n|
      [ n, "Plan #{n}", "#{n * 3} €", "#{n * 10} GB", n * 2, n.even? ? "Email" : "**Phone**", %w[Europe Americas Asia][n % 3],
        "A longer cell of words that wraps inside its column on a narrow screen" ]
    end
    markdown = [ head, head.map.with_index { |_, i| [ 2, 4 ].include?(i) ? "---:" : "---" }, *rows ].map { |cells| "| #{cells.join(" | ")} |" }.join("\n")
    body(markdown, tables: true)
  end

  def intro
    <<~MARKDOWN
      Every block type this site has, drawn by the theme: [every block](/showcase/every-block) at the top level; every type in a section of every layout, on [no band](/showcase/band-none), a [tinted band](/showcase/band-tinted) and a [strong band](/showcase/band-strong); [every note](/showcase/every-note); [a long table](/showcase/a-long-table); [every list](/showcase/every-list).

      [This link goes to no page](/showcase/no-such-page), so it shows the site's 404 page.
    MARKDOWN
  end

  def body(markdown, tables: false)
    document, warnings = RichText::Document.from_markdown(markdown, tables: tables)
    raise "seeds: #{warnings.to_sentence}" if warnings.any?

    document.to_h
  end
end
