require "test_helper"

# A save that changes nothing changes nothing: the same content sent again
# (a loader's or an import's second run, an autosave of a form that holds
# what is stored) leaves a live record unmarked, moves no base a stale check
# reads and writes no audit event, and still answers ok.
#
# `ContentBlocks::Save` used to touch its page whatever the save wrote, and a
# touched live page is marked as having unpublished changes
# (`Publishable#note_unpublished_changes_on_touch`): a second load of
# unchanged content left 56 live pages "with unpublished changes" and nothing
# to publish. `Pages::Save` and `Posts::Save` never did (a record with no
# change issues no UPDATE and runs no touch); they are held here beside it so
# the three stay alike.
class NoChangeSaveTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Live page")
    @text = add_block("rich_text", translations: { Locales.default => { body: rich_doc("Hello **world**") } })
    @list = add_block("post_list", attributes: { settings: { "limit" => 5 } })
    @image = add_block("image", attributes: { media_asset_id: create_media_asset.id },
      translations: { Locales.default => { caption: "A caption", alt: "An alt text" } })
    @section = add_block("section", attributes: { settings: { "layout" => "two" } })
    @inside = add_block("rich_text", attributes: { section_id: @section.id, section_column: 2 },
      translations: { Locales.default => { body: rich_doc("In a lane") } })
    @post = create_post(title: "Live post", tags: %w[alpha beta])
    assert Posts::Save.call(@post, translations: { Locales.default => { body: rich_doc("A body"), excerpt: "An excerpt" } }).ok?
    publish_changes(@page)
    publish_changes(@post)
    assert_nil @page.reload.unpublished_changes_at
    assert_nil @post.reload.unpublished_changes_at
    # A minute on, so a touch that should not happen is a different time.
    travel 1.minute
  end

  # Everything a no-change save must leave alone: the marks, every base a
  # stale check reads (a block's and a post's `updated_at`, a page's
  # `settings_changed_at`), the page's `updated_at` the lists order by, the
  # audit log and the public content version.
  def state
    {
      page: @page.reload.attributes.slice("updated_at", "settings_changed_at", "unpublished_changes_at"),
      post: @post.reload.attributes.slice("updated_at", "unpublished_changes_at"),
      blocks: ContentBlock.where(owner: @page).order(:id).pluck(:id, :updated_at),
      events: Audit::Event.count,
      version: PublicSite.content_version
    }
  end

  def add_block(type, attributes: {}, translations: {})
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: type }.merge(attributes), translations: translations)
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def assert_nothing_moved(label)
    before = state
    result = yield
    assert result.ok?, "#{label}: #{result.errors.to_sentence}"
    assert_equal before, state, "#{label} changed nothing and yet moved something"
    assert_nil @page.unpublished_changes_at, "#{label} marked the live page"
    assert_nil @post.unpublished_changes_at, "#{label} marked the live post"
  end

  def block(record) = ContentBlock.find(record.id)

  test "a block saved with the body it has marks nothing, whether the body arrives as a Hash, as JSON or as a document" do
    stored = @text.reload.body_document(locale: Locales.default)

    assert_nothing_moved("a Hash") { ContentBlocks::Save.call(block(@text), translations: { Locales.default => { body: rich_doc("Hello **world**") } }) }
    assert_nothing_moved("a JSON string") { ContentBlocks::Save.call(block(@text), translations: { Locales.default => { body: stored.to_h.to_json } }) }
    assert_nothing_moved("a document") { ContentBlocks::Save.call(block(@text), translations: { Locales.default => { body: stored } }) }
    assert_nothing_moved("nothing at all") { ContentBlocks::Save.call(block(@text)) }
  end

  test "a block saved with the settings, the image, the caption and the place it has marks nothing, as a form sends them" do
    assert_nothing_moved("settings as stored") { ContentBlocks::Save.call(block(@list), attributes: { settings: { "limit" => 5 } }) }
    assert_nothing_moved("settings as a form's strings") { ContentBlocks::Save.call(block(@list), attributes: { block_type: "post_list", position: @list.position.to_s, settings: { "limit" => "5" } }, translations: { Locales.default => {} }) }
    assert_nothing_moved("an image block's fields") do
      ContentBlocks::Save.call(block(@image), attributes: { media_asset_id: @image.media_asset_id.to_s },
        translations: { Locales.default => { caption: "A caption", alt: "An alt text" } })
    end
    assert_nothing_moved("a section's layout") { ContentBlocks::Save.call(block(@section), attributes: { settings: { "layout" => "two" } }) }
    assert_nothing_moved("a block in a section, its place echoed back") do
      ContentBlocks::Save.call(block(@inside), attributes: { section_id: @section.id, section_column: 2 }, translations: { Locales.default => { body: rich_doc("In a lane") } })
    end
  end

  test "a no-change block save still takes the page's row lock, and writes neither the block nor the page" do
    statements = capture_sql { assert ContentBlocks::Save.call(block(@text), translations: { Locales.default => { body: rich_doc("Hello **world**") } }).ok? }

    assert_equal 1, statements.count { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
    assert_empty statements.grep(/\AUPDATE "(content_blocks|pages)"/)
  end

  test "a page saved with the settings it has, and a post with the fields, body and tags it has, mark nothing" do
    assert_nothing_moved("the page") do
      Pages::Save.call(Page.find(@page.id), attributes: {}, translations: { Locales.default => { title: "Live page" } })
    end
    assert_nothing_moved("the post") do
      Posts::Save.call(Post.find(@post.id), attributes: { tag_names: %w[alpha beta] },
        translations: { Locales.default => { title: "Live post", excerpt: "An excerpt", body: rich_doc("A body") } })
    end
  end

  test "a real change of a block still marks its live page, moves the page's updated_at and is audited: a body, one settings key, one language's caption" do
    changes = {
      "a body" => -> { ContentBlocks::Save.call(block(@text), translations: { Locales.default => { body: rich_doc("Hello **there**") } }) },
      "one settings key" => -> { ContentBlocks::Save.call(block(@list), attributes: { settings: { "limit" => 6 } }) },
      "a caption" => -> { ContentBlocks::Save.call(block(@image), translations: { Locales.default => { caption: "Another caption" } }) }
    }

    changes.each do |label, change|
      # The round before left the page marked: start each from "published".
      publish_changes(@page) if @page.reload.unpublished_changes_at
      travel 1.minute
      before = state
      assert_nil before[:page]["unpublished_changes_at"]

      assert change.call.ok?, label

      after = state
      assert_not_nil after[:page]["unpublished_changes_at"], "#{label} did not mark the live page"
      assert_operator after[:page]["updated_at"], :>, before[:page]["updated_at"], label
      assert_equal before[:page]["settings_changed_at"], after[:page]["settings_changed_at"], "#{label} moved the settings form's base"
      assert_operator after[:events], :>, before[:events], label
    end
  end

  # A fold writes other blocks' rows and may write nothing of the section's
  # own: it is a change of the page all the same.
  test "a section's save that only folds a stranded block marks the page, though the section's own row is unchanged" do
    @inside.update_columns(section_column: 3) # as a second tab's widening and add would have left it
    before = state

    assert ContentBlocks::Save.call(block(@section), attributes: { settings: { "layout" => "two" } }).ok?

    assert_equal 2, @inside.reload.section_column
    assert_not_nil @page.reload.unpublished_changes_at
    assert_operator @page.updated_at, :>, before[:page]["updated_at"]
    assert_equal before[:blocks].to_h[@section.id], @section.reload.updated_at
  end

  test "a no-change save of a draft page's block leaves the draft's updated_at where it was, and a change moves it" do
    draft = create_page(title: "Draft", published: false)
    text = ContentBlocks::Save.call(ContentBlock.new(owner: draft), attributes: { block_type: "rich_text" }, translations: { Locales.default => { body: rich_doc("Draft text") } }).record
    travel 1.minute
    before = draft.reload.updated_at

    assert ContentBlocks::Save.call(block(text), translations: { Locales.default => { body: rich_doc("Draft text") } }).ok?
    assert_equal before, draft.reload.updated_at

    assert ContentBlocks::Save.call(block(text), translations: { Locales.default => { body: rich_doc("Draft text, edited") } }).ok?
    assert_operator draft.reload.updated_at, :>, before
  end
end
