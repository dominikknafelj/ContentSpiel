require "test_helper"

class BuiltInTypesTest < ActiveSupport::TestCase
  test "built-ins are registered" do
    assert_equal %w[rich_text image code post_list section], BlockTypes.names
    assert_equal %w[blog resume_entry now_update], ContentTypes.names
    assert BlockTypes.fetch(:post_list).capability?(:lists_posts)
    assert_equal %w[image caption alt], BlockTypes.fetch(:image).uses_columns
  end

  test "code is a block of three settings and a caption, none of them required, the code never translated" do
    code = BlockTypes.fetch(:code)

    assert_equal "Code", code.label
    assert_equal [ %w[language select], %w[filename string], %w[code code] ], code.fields.map { |field| [ field.name, field.type.to_s ] }
    assert_equal %w[caption], code.uses_columns
    assert_not code.capability?(:code), "the capability's one reader was the tile's branch, which is the type's summary now"
    assert_equal %w[block page lines code language language_label filename caption string], code.theme_methods
    assert_equal CodeHighlight::ROLES.map { |role| "syn-#{role}" }, code.themed_tokens
    assert_equal "code.css", code.stylesheet
    assert_equal %w[admin--editor--code-limit#update], code.read_only_actions
    # The values of the hand-written rows the sample replaced (the scaffold's
    # /wide and the canary's Alpha, block types review I2): markup-looking ERB
    # coloured as ERB, and a caption in each of the three languages.
    assert_equal [ "show.html.erb", %(<span class="syn-embed">), "A template" ], code.sample.shows
    assert_equal({ "language" => "erb", "filename" => "show.html.erb", "code" => "<p class=\"a\"><%= 1 %></p>\n<%# note %>" }, code.sample.settings)
    assert_equal %w[en de es], code.sample.translations.keys
    assert_equal Blocks::CodeComponent, code.component
    assert code.fields.none? { |field| field.required? || field.translated? }
    assert_equal CodeHighlight::LANGUAGES, code.fields.first.options[:options]
    assert_equal "Plain text", code.fields.first.options[:blank]
    assert_equal 20_000, code.fields.last.options[:max]
  end

  test "section is the one container type, and its columns follow its layout" do
    assert_equal [ "section" ], BlockTypes.with_capability(:container).map(&:name)
    assert_equal 3, BlockTypes.fetch(:section).columns.call("layout" => "three")
    assert_equal [ 1, 2 ], BlockTypes::Section.weights("one_two")
    assert_equal [ 1, 1 ], BlockTypes::Section.weights("no such layout")
  end

  # `ContentBlock#column_count` calls the type's `columns` without a guard, so
  # a container type that doesn't say how many it has is refused when it is
  # registered, not when a page renders.
  test "a container type registered without columns is refused" do
    saved = BlockTypes.all.dup

    error = assert_raises(ArgumentError) { BlockTypes.register(:test_band) { |t| t.label "Band"; t.capability :container } }
    assert_equal "a container block type needs `columns`", error.message
  ensure
    BlockTypes.reset!
    saved.each { |definition| BlockTypes.registry_put(definition) }
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

    assert_nothing_raised { PublicSite::Paths.refresh(posts: [ post ]) }
    assert_nil post.reload.full_path("en")
    assert_nil block.reload.definition
    assert_empty page.content_blocks.listing
  end

  test "rich text and image declare their contract lines and a sample, and need no summary, token, stylesheet or action of their own" do
    rich_text = BlockTypes.fetch(:rich_text)
    image = BlockTypes.fetch(:image)

    assert_equal %w[block page], rich_text.theme_methods
    assert_equal %w[block page asset alt caption sizes], image.theme_methods
    [ rich_text, image ].each do |definition|
      assert_nil definition.summary
      assert_empty definition.themed_tokens + definition.fixed_tokens + definition.read_only_actions
      assert_nil definition.stylesheet
    end
    assert rich_text.sample.body.present?
    assert image.sample.image
    assert_equal %w[alt caption], image.sample.translations.fetch("en").keys.map(&:to_s).sort
  end
end
