require "test_helper"

class Admin::ContentBlocksTest < ActionDispatch::IntegrationTest
  # `perform_enqueued_jobs` (fix round 1's duplicate-blob test): a
  # `has_one_attached` detach/destroy purges its blob via `:purge_later`, an
  # `ActiveJob` -- the test queue adapter never runs one on its own, so
  # without this helper `source.destroy` below would leave the (buggy,
  # shared) blob un-purged and the very bug this test exists to catch would
  # pass by accident.
  include ActiveJob::TestHelper
  include TestTypes

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    @page = create_page(title: "About")
  end

  def blocks_path = "/cs-studio/pages/#{@page.id}/content_blocks"

  test "adding a block streams its card in" do
    post blocks_path, params: { block: { block_type: "post_list" } }, as: :turbo_stream
    assert_response :success
    block = @page.content_blocks.last
    assert_equal "post_list", block.block_type
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(block)
  end

  test "typed settings autosave with per-field errors" do
    block = @page.content_blocks.create!(block_type: "post_list", position: 0)
    patch "#{blocks_path}/#{block.id}", params: { block: { settings: { limit: "0" } }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_includes response.body, "must be greater than or equal to 1"

    patch "#{blocks_path}/#{block.id}", params: { block: { settings: { limit: "3" } }, base_updated_at: block.reload.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_equal 3, block.reload.settings_object.limit
  end

  test "saving a block in a section streams its tile's summary, and a block outside one does not" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    inside = @page.content_blocks.create!(block_type: "post_list", section: section, section_column: 1, position: 0)
    outside = @page.content_blocks.create!(block_type: "post_list", position: 1)

    patch "#{blocks_path}/#{inside.id}", params: { block: { settings: { limit: "0" } }, base_updated_at: inside.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_includes response.body, "block-#{inside.id}-tile-summary"
    assert_includes response.body, "Needs fixing"

    patch "#{blocks_path}/#{outside.id}", params: { block: { settings: { limit: "3" } }, base_updated_at: outside.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_not_includes response.body, "tile-summary"
  end

  test "a saved block in a section streams the summary of what was saved, and a refused stale save streams none" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    inside = @page.content_blocks.create!(block_type: "post_list", section: section, section_column: 1, position: 0)
    base = inside.updated_at.iso8601(6)

    patch "#{blocks_path}/#{inside.id}", params: { block: { settings: { tag: "rails" } }, base_updated_at: base }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=replace][target='block-#{inside.id}-tile-summary']" do
      assert_select "template", text: /All posts · tag rails/
    end
    assert_not_includes response.body, "Needs fixing"

    travel 1.minute do
      patch "#{blocks_path}/#{inside.id}", params: { block: { settings: { tag: "ruby" } }, base_updated_at: base }, as: :turbo_stream
    end
    assert_response :conflict
    assert_not_includes response.body, "tile-summary"
  end

  # A block in a section is two elements, its tile and its form's panel
  # (sections spec §4.3). An unavailable block's panel has "Delete block…",
  # so the panel can be the very thing on screen when its block is deleted.
  test "deleting a block in a section removes its tile and its panel, and a block outside one only its card" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    inside = @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
    outside = @page.content_blocks.create!(block_type: "rich_text", position: 1)

    delete "#{blocks_path}/#{inside.id}", as: :turbo_stream
    assert_response :success
    assert_not ContentBlock.exists?(inside.id)
    assert_select "turbo-stream[action=remove][target='#{ActionView::RecordIdentifier.dom_id(inside)}']"
    assert_select "turbo-stream[action=remove][target='block-#{inside.id}-panel']"

    delete "#{blocks_path}/#{outside.id}", as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=remove]", count: 1
    assert_select "turbo-stream[action=remove][target='#{ActionView::RecordIdentifier.dom_id(outside)}']"
  end

  # A section's header counts its blocks, and a delete is the one write that
  # changes the count without redrawing anything else of the card.
  test "deleting a block in a section streams the section's new count, and a block outside one streams none" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    inside = @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
    @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 2, position: 0)
    outside = @page.content_blocks.create!(block_type: "rich_text", position: 1)

    delete "#{blocks_path}/#{inside.id}", as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=replace][target='section-#{section.id}-summary'] template" do
      assert_select "#section-#{section.id}-summary", text: "2 columns · 1 block"
    end

    delete "#{blocks_path}/#{outside.id}", as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[target$='-summary']", count: 0
  end

  test "adding into a column streams the panel, then the tile, marked to open, and the section's count" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)

    post blocks_path, params: { block: { block_type: "image" }, section_id: section.id, column: 2 }, as: :turbo_stream

    assert_response :created
    block = section.section_blocks.sole
    assert_equal 2, block.section_column
    panel = response.body.index(%(id="block-#{block.id}-panel"))
    tile = response.body.index(%(id="#{ActionView::RecordIdentifier.dom_id(block)}"))
    assert panel && tile && panel < tile, "the panel must arrive before its tile"
    assert_includes response.body, %(target="section-#{section.id}-panels")
    assert_includes response.body, %(target="section-#{section.id}-lane-2")
    assert_includes response.body, "data-open"
    assert_includes response.body, "1 block"
    assert_select "turbo-stream[action=append][target='section-#{section.id}-panels'] template" do
      assert_select "#block-#{block.id}-panel[hidden][data-open][data-admin--section-target='panel']"
    end
    assert_select "turbo-stream[action=append][target='section-#{section.id}-lane-2'] template" do
      assert_select "##{ActionView::RecordIdentifier.dom_id(block)}.admin-block-tile .admin-block-tile__face[aria-expanded='true']"
    end
    assert_select "turbo-stream[target='content-blocks-list']", count: 0
  end

  test "a second block added to a column lands after the first, and the count follows" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    first = @page.content_blocks.create!(block_type: "image", section: section, section_column: 2, position: 0)

    post blocks_path, params: { block: { block_type: "rich_text" }, section_id: section.id, column: 2 }, as: :turbo_stream

    assert_response :created
    assert_equal [ first.id, section.section_blocks.where.not(id: first.id).sole.id ], ContentBlock.in_column(section.id, 2).reorder(:position).ids
    assert_includes response.body, "2 blocks"
  end

  test "adding into a column the section no longer has is refused with a message and the lanes as they are" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })

    assert_no_difference -> { ContentBlock.count } do
      post blocks_path, params: { block: { block_type: "image" }, section_id: section.id, column: 4 }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
    assert_includes response.body, "content-blocks-alert"
    assert_includes response.body, "isn&#39;t a column of this section"
    assert_includes response.body, %(target="section-#{section.id}-lanes")
  end

  # Review Focus of the sections plan: two tabs. One was loaded while the
  # section had four columns and still shows the "+" of the fourth; the other
  # has since folded the section to two. The first tab's add is refused, no
  # block ends in a column that isn't there, and the answer redraws the lanes
  # as they are now -- two, the folded block at the end of the second.
  test "an add into a column another tab folded away is refused, and the answer draws the lanes as they are now" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "four" })
    kept = @page.content_blocks.create!(block_type: "image", section: section, section_column: 2, position: 0)
    folded = @page.content_blocks.create!(block_type: "image", section: section, section_column: 4, position: 0)

    patch "#{blocks_path}/#{section.id}", params: { block: { settings: { layout: "two" } }, base_updated_at: section.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_equal [ 2, 1 ], folded.reload.values_at(:section_column, :position)

    assert_no_difference -> { ContentBlock.count } do
      post blocks_path, params: { block: { block_type: "image" }, section_id: section.id, column: 4 }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_select "turbo-stream[action=replace][target='content-blocks-alert'] template", text: /isn't a column of this section/
    assert_select "turbo-stream[action=replace][target='section-#{section.id}-lanes'] template" do
      assert_select "#section-#{section.id}-lanes [data-admin--blocks-target='lane']", count: 2
      assert_equal [ kept.id, folded.id ], css_select("#section-#{section.id}-lane-2 > .admin-block-tile").map { |tile| tile["data-block-id"].to_i }
      assert_select "#section-#{section.id}-lane-4", count: 0
    end
    assert_equal [], ContentBlock.where(section_id: section.id, section_column: 3..).ids
  end

  test "a narrower layout answers with the lanes redrawn, the folded blocks' headings and the count" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "three" })
    moved = @page.content_blocks.create!(block_type: "image", section: section, section_column: 3, position: 0)

    patch "#{blocks_path}/#{section.id}", params: { block: { settings: { layout: "two", background: "none", width: "content" } }, base_updated_at: section.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_equal 2, moved.reload.section_column
    assert_includes response.body, %(target="section-#{section.id}-lanes")
    assert_includes response.body, %(target="block-#{moved.id}-panel-title")
    assert_includes response.body, "Image · column 2"
    assert_includes response.body, "2 columns"
  end

  # What that answer must not do: replace a panel. Its form may hold text
  # that is not saved yet, and its registration with the write queue.
  test "a layout save rewrites each heading and never a panel, and its layout menu follows the saved layout" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "three" })
    stays = @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
    moved = @page.content_blocks.create!(block_type: "image", section: section, section_column: 3, position: 0)

    patch "#{blocks_path}/#{section.id}", params: { block: { settings: { layout: "one", background: "none", width: "content" } }, base_updated_at: section.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action=update][target='block-#{stays.id}-panel-title'] template", text: "Rich text · column 1"
    assert_select "turbo-stream[action=update][target='block-#{moved.id}-panel-title'] template", text: "Image · column 1"
    assert_select "turbo-stream[target='block-#{moved.id}-panel']", count: 0
    assert_select "turbo-stream[target='block-#{stays.id}-panel']", count: 0
    assert_select "turbo-stream[action=replace][target='section-#{section.id}-summary'] template", text: "1 column · 2 blocks"
    assert_select "turbo-stream[action=replace][target='section-#{section.id}-layout-menu'] template" do
      assert_select "button[data-admin--section-layout-param='one'][aria-current='true']"
      assert_select "button[aria-current='true']", count: 1
    end
    assert_select "turbo-stream[action=replace][target='block-#{section.id}-base-updated-at']"
    assert_select "turbo-stream[action=replace][target='block-#{section.id}-save-status']"
  end

  # The lanes are tiles a person may be dragging or have a menu open in:
  # they are redrawn only by a save that changed how many columns there are.
  test "a save of the background alone leaves the lanes as they are, and a layout of as many columns redraws only its menu" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    @page.content_blocks.create!(block_type: "image", section: section, section_column: 2, position: 0)

    patch "#{blocks_path}/#{section.id}", params: { block: { settings: { layout: "two", background: "tinted", width: "full" } }, base_updated_at: section.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_equal %w[two tinted full], section.reload.settings.values_at("layout", "background", "width")
    assert_select "turbo-stream[target='section-#{section.id}-lanes']", count: 0
    assert_select "turbo-stream[target$='-panel-title']", count: 0
    # Nor the layout menu: it may be open, or its button hold the focus.
    assert_select "turbo-stream[target='section-#{section.id}-layout-menu']", count: 0

    patch "#{blocks_path}/#{section.id}", params: { block: { settings: { layout: "one_two", background: "tinted", width: "full" } }, base_updated_at: section.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[target='section-#{section.id}-lanes']", count: 0
    assert_select "turbo-stream[action=replace][target='section-#{section.id}-layout-menu'] template button[data-admin--section-layout-param='one_two'][aria-current='true']"
  end

  test "the first save of a section that stores no settings yet is no change of layout" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    section.update_column(:settings, {})

    patch "#{blocks_path}/#{section.id}", params: { block: { settings: { layout: "two", background: "tinted", width: "content" } }, base_updated_at: section.reload.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :success
    assert_equal "tinted", section.reload.settings["background"]
    assert_select "turbo-stream[target='section-#{section.id}-layout-menu']", count: 0
    assert_select "turbo-stream[target='section-#{section.id}-lanes']", count: 0
  end

  test "a section's setting the registry doesn't know is refused into its own error slot, and nothing is redrawn" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "three" })
    moved = @page.content_blocks.create!(block_type: "image", section: section, section_column: 3, position: 0)

    patch "#{blocks_path}/#{section.id}", params: { block: { settings: { layout: "five", background: "none", width: "content" } }, base_updated_at: section.updated_at.iso8601(6) }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_equal 3, moved.reload.section_column
    assert_select "turbo-stream[action=replace][target='block-#{section.id}-layout-errors'] template p"
    assert_select "turbo-stream[target='section-#{section.id}-lanes']", count: 0
    assert_select "turbo-stream[target='section-#{section.id}-layout-menu']", count: 0
  end

  test "a stale save of a section is refused with a 409 and folds nothing" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "three" })
    moved = @page.content_blocks.create!(block_type: "image", section: section, section_column: 3, position: 0)
    base = section.updated_at.iso8601(6)
    travel(1.minute) { ContentBlocks::Save.call(section, attributes: { settings: { "background" => "tinted" } }, actor: nil) }

    patch "#{blocks_path}/#{section.id}", params: { block: { settings: { layout: "one" } }, base_updated_at: base }, as: :turbo_stream

    assert_response :conflict
    assert_equal 3, moved.reload.section_column
  end

  # Carried from the lane picker's review: the lanes an add was refused into
  # are drawn as they are now, and so is everything that names a column --
  # the headings of the forms under them and the header's count.
  test "an add refused because the column is gone redraws the headings and the count with the lanes" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "four" })
    folded = @page.content_blocks.create!(block_type: "image", section: section, section_column: 4, position: 0)
    patch "#{blocks_path}/#{section.id}", params: { block: { settings: { layout: "two" } }, base_updated_at: section.updated_at.iso8601(6) }, as: :turbo_stream

    post blocks_path, params: { block: { block_type: "image" }, section_id: section.id, column: 4 }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select "turbo-stream[action=replace][target='section-#{section.id}-lanes']"
    assert_select "turbo-stream[action=update][target='block-#{folded.id}-panel-title'] template", text: "Image · column 2"
    assert_select "turbo-stream[action=replace][target='section-#{section.id}-summary'] template", text: "2 columns · 1 block"
    assert_select "turbo-stream[target='block-#{folded.id}-panel']", count: 0
    # Not the layout menu: the form it belongs to holds the layout this tab
    # loaded, and its next save is refused as stale and says so.
    assert_select "turbo-stream[target='section-#{section.id}-layout-menu']", count: 0
  end

  test "removing a section and keeping its blocks puts their cards where the section was" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    kept = @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)

    delete "#{blocks_path}/#{section.id}", params: { keep_blocks: 1 }, as: :turbo_stream

    assert_response :success
    assert_nil kept.reload.section_id
    assert_includes response.body, %(action="replace" target="#{ActionView::RecordIdentifier.dom_id(section)}")
    assert_includes response.body, %(id="#{ActionView::RecordIdentifier.dom_id(kept)}")
    assert_includes response.body, "admin-block-card"
  end

  test "the kept blocks' cards come in reading order as cards of the list, first and last as they now are" do
    before = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    section = @page.content_blocks.create!(block_type: "section", position: 1)
    right = @page.content_blocks.create!(block_type: "image", section: section, section_column: 2, position: 0)
    left = @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)

    delete "#{blocks_path}/#{section.id}", params: { keep_blocks: 1 }, as: :turbo_stream

    assert_response :success
    assert_equal [ before.id, left.id, right.id ], @page.content_blocks.top_level.reorder(:position).ids
    assert_select "turbo-stream[action=replace][target='#{ActionView::RecordIdentifier.dom_id(section)}'] template" do
      assert_equal [ left.id, right.id ], css_select(".admin-block-card[data-admin--blocks-target='card']").map { |card| card["data-block-id"].to_i }
      assert_select "[data-admin--section-target]", count: 0
      assert_select "##{ActionView::RecordIdentifier.dom_id(left)} button[data-move='up']:not([disabled])"
      assert_select "##{ActionView::RecordIdentifier.dom_id(right)} button[data-move='down'][disabled]"
    end
  end

  test "removing an empty section and keeping its blocks removes its card" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)

    delete "#{blocks_path}/#{section.id}", params: { keep_blocks: 1 }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action=remove][target='#{ActionView::RecordIdentifier.dom_id(section)}']"
    assert_empty @page.content_blocks.reload
  end

  test "deleting a section removes its card, and deleting a block in a section removes its tile and panel and recounts" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    a = @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
    @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 1)

    delete "#{blocks_path}/#{a.id}", as: :turbo_stream
    assert_response :success
    assert_includes response.body, %(action="remove" target="#{ActionView::RecordIdentifier.dom_id(a)}")
    assert_includes response.body, %(action="remove" target="block-#{a.id}-panel")
    assert_includes response.body, "1 block"
    assert_select "turbo-stream[action=replace][target='section-#{section.id}-delete-count'] template", text: "This also deletes the 1 block in it."

    delete "#{blocks_path}/#{section.id}", as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=remove][target='#{ActionView::RecordIdentifier.dom_id(section)}']"
    assert_empty @page.content_blocks.reload
  end

  test "a reader's delete of a section, with or without its blocks, is refused and nothing leaves" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    inside = @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
    sign_in_as(users(:reader))

    delete "#{blocks_path}/#{section.id}", params: { keep_blocks: 1 }, as: :turbo_stream
    assert_response :forbidden
    delete "#{blocks_path}/#{section.id}", as: :turbo_stream
    assert_response :forbidden

    assert_equal section.id, inside.reload.section_id
    assert_select "turbo-stream[target='#{ActionView::RecordIdentifier.dom_id(section)}']", count: 0
  end

  test "adding into a section that is gone is refused, and a section can't be added into a section" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)

    post blocks_path, params: { block: { block_type: "image" }, section_id: 0, column: 1 }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_includes response.body, "That section or column no longer exists"
    post blocks_path, params: { block: { block_type: "section" }, section_id: section.id, column: 1 }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_equal [ section ], @page.content_blocks.reload.to_a
  end

  # `section_id` is looked up among this page's blocks, like every block id
  # here: another page's section is "gone" to this request, and a block that
  # is no section holds nothing (the answer has no lanes to redraw).
  test "an add can't name another page's section, or a block that is no section" do
    other = create_page(title: "Elsewhere").content_blocks.create!(block_type: "section", position: 0)
    plain = @page.content_blocks.create!(block_type: "rich_text", position: 0)

    assert_no_difference -> { ContentBlock.count } do
      post blocks_path, params: { block: { block_type: "image" }, section_id: other.id, column: 1 }, as: :turbo_stream
      assert_response :unprocessable_entity
      assert_includes response.body, "That section or column no longer exists"

      post blocks_path, params: { block: { block_type: "image" }, section_id: plain.id, column: 1 }, as: :turbo_stream
      assert_response :unprocessable_entity
      assert_select "turbo-stream[target$='-lanes']", count: 0
    end
  end

  test "a viewer who can't edit the page is refused an add into a column, with no lanes in the answer" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    sign_in_as(users(:reader))

    assert_no_difference -> { ContentBlock.count } do
      post blocks_path, params: { block: { block_type: "image" }, section_id: section.id, column: 1 }, as: :turbo_stream
    end
    assert_response :forbidden
    assert_select "turbo-stream[target$='-lanes']", count: 0
  end

  test "adding a section streams its card with empty lanes" do
    post blocks_path, params: { block: { block_type: "section" } }, as: :turbo_stream

    assert_response :created
    section = @page.content_blocks.sole
    assert_includes response.body, "admin-section-card"
    assert_includes response.body, "section-#{section.id}-lane-2"
  end

  test "the page editor draws a section as a card of lanes with every block's form under them, and only on the default language's tab" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    inside = @page.content_blocks.create!(block_type: "image", section: section, section_column: 2, position: 0)
    outside = @page.content_blocks.create!(block_type: "rich_text", position: 1)

    get "/cs-studio/pages/#{@page.id}"
    assert_response :success
    assert_select "#content-blocks-list > .admin-block-card", count: 2
    assert_select "#content-blocks-list > ##{ActionView::RecordIdentifier.dom_id(section)}.admin-section-card[data-controller~='admin--section']"
    assert_select "#section-#{section.id}-lane-2 > ##{ActionView::RecordIdentifier.dom_id(inside)}.admin-block-tile"
    assert_select "#section-#{section.id}-panels > #block-#{inside.id}-panel[hidden] form[action$='/content_blocks/#{inside.id}']"
    assert_select "#content-blocks-list > ##{ActionView::RecordIdentifier.dom_id(outside)}[data-admin--blocks-target='card']"

    get "/cs-studio/pages/#{@page.id}", params: { locale: "de" }
    assert_response :success
    assert_select ".admin-section-card", count: 0
    assert_select "#content-blocks-list > ##{ActionView::RecordIdentifier.dom_id(section)}[data-admin--blocks-target='card']"
  end

  test "an Undo of a reorder re-renders a section as its card, tiles and forms included" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    inside = @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
    other = @page.content_blocks.create!(block_type: "rich_text", position: 1)

    patch "#{blocks_path}/reorder", params: { ids: [ section.id, other.id ], undo: 1 }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=update][target='content-blocks-list'] template" do
      assert_select ".admin-section-card ##{ActionView::RecordIdentifier.dom_id(inside)}.admin-block-tile"
      assert_select ".admin-section-card #block-#{inside.id}-panel[hidden]"
    end
  end

  # One "Add block" row at the end of the list (design pass round 2): the
  # between-cards pickers are gone, so an append only streams the new card in
  # before that row -- nothing about the previously-last card changes (its
  # Move down is re-enabled client-side, `admin--blocks#refreshMoveState`).
  test "adding a block appends its card to the list and replaces nothing else" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)

    post blocks_path, params: { block: { block_type: "rich_text" } }, as: :turbo_stream
    assert_response :success

    new_block = @page.content_blocks.order(:position).last
    assert_select "turbo-stream[action='append'][target='content-blocks-list']", count: 1
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(new_block)
    assert_not_includes response.body, "block-picker-after-"
    assert_not_includes response.body, %(<turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(first)}">)
  end

  test "the new last card renders its Move down disabled, and Move up enabled when it is not first" do
    @page.content_blocks.create!(block_type: "rich_text", position: 0)

    post blocks_path, params: { block: { block_type: "rich_text" } }, as: :turbo_stream
    assert_response :success

    card = Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[action='append'] template")
    assert card.at_css("button[data-move='down'][disabled]"), "the last card cannot move down"
    assert_nil card.at_css("button[data-move='up'][disabled]")
  end

  test "after_id is still honoured by create: the card lands right after that block" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    second = @page.content_blocks.create!(block_type: "rich_text", position: 1)

    post blocks_path, params: { block: { block_type: "rich_text" }, after_id: first.id }, as: :turbo_stream
    assert_response :success

    added = (@page.content_blocks.reload.to_a - [ first, second ]).sole
    assert_equal [ first, added, second ], @page.content_blocks.to_a
    assert_select "turbo-stream[action='after'][target='#{ActionView::RecordIdentifier.dom_id(first)}']", count: 1
    assert_not_includes response.body, %(<turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(second)}">)
  end

  test "duplicating a block streams the copy in right after the source and replaces no other card" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    second = @page.content_blocks.create!(block_type: "rich_text", position: 1)

    post "#{blocks_path}/#{first.id}/duplicate", as: :turbo_stream
    assert_response :success

    copy = (@page.content_blocks.reload.to_a - [ first, second ]).sole
    assert_equal [ first, copy, second ], @page.content_blocks.to_a
    assert_select "turbo-stream[action='after'][target='#{ActionView::RecordIdentifier.dom_id(first)}']", count: 1
    assert_not_includes response.body, %(<turbo-stream action="replace")
  end

  test "typed-setting errors name their field in words in the block's error slot" do
    block = @page.content_blocks.create!(block_type: "post_list", position: 0)
    prefix = Admin::BlockCardComponent.error_prefix(block)

    patch "#{blocks_path}/#{block.id}", params: { block: { settings: { limit: "0" } }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_select_in_stream "#{prefix}-limit-errors", /\A\s*!?\s*Limit must be greater than or equal to 1\s*\z/
  end

  test "reorder, duplicate and delete" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    second = @page.content_blocks.create!(block_type: "rich_text", position: 1)
    patch "#{blocks_path}/reorder", params: { ids: [ second.id, first.id ] }, as: :turbo_stream
    assert_equal [ second, first ], @page.content_blocks.reload.to_a

    post "#{blocks_path}/#{first.id}/duplicate", as: :turbo_stream
    assert_equal 3, @page.content_blocks.count

    delete "#{blocks_path}/#{first.id}", as: :turbo_stream
    assert_not ContentBlock.exists?(first.id)
  end

  test "a reorder answers with an Undo toast that restores the previous order and the list" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    second = @page.content_blocks.create!(block_type: "rich_text", position: 1)
    third = @page.content_blocks.create!(block_type: "rich_text", position: 2)

    patch "#{blocks_path}/reorder", params: { ids: [ third.id, first.id, second.id ] }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action='append'][target='toasts'] .admin-toast[data-kind='undo']", text: /order changed/i
    undo = css_select("turbo-stream[target='toasts'] form").first
    assert_equal "patch", css_select(undo, "input[name='_method']").first["value"]
    query = Rack::Utils.parse_nested_query(URI.parse(undo["action"]).query)
    assert_equal [ first.id, second.id, third.id ].map(&:to_s), query["ids"]
    assert_equal "1", query["undo"]

    # The Undo goes through the same service and answers by re-rendering the
    # list in the restored order (the client's DOM is still the dropped one).
    patch undo["action"], as: :turbo_stream
    assert_response :success
    assert_equal [ first, second, third ], @page.content_blocks.reload.to_a
    assert_select "turbo-stream[action='update'][target='content-blocks-list']"
    ids = Nokogiri::HTML5.fragment(response.body).css("turbo-stream[target='content-blocks-list'] [data-block-id]").map { |card| card["data-block-id"] }
    assert_equal [ first.id, second.id, third.id ].map(&:to_s), ids
    assert_select "turbo-stream[target='toasts'] .admin-toast form", count: 0
  end

  test "a reorder that changes nothing offers no Undo" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    second = @page.content_blocks.create!(block_type: "rich_text", position: 1)
    patch "#{blocks_path}/reorder", params: { ids: [ first.id, second.id ] }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[target='toasts']", count: 0
  end

  test "a refused reorder offers no Undo" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    patch "#{blocks_path}/reorder", params: { ids: [ first.id, 0 ] }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_select "turbo-stream[target='toasts']", count: 0
  end

  # Fix round 1 (Task 7 review): regression test for the `Admin::Columns::
  # RichTextColumnComponent` fix (`name` -> `html_name`) -- the body has to
  # arrive nested as `block[body]` or `split_block_params`'s own
  # `block_params.key?(:body)` check never sees it. Since the JSON-document
  # switch the param is the hidden input's document JSON String.
  test "a rich_text block's body autosaves" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    patch "#{blocks_path}/#{block.id}", params: { block: { body: rich_doc("Hello there").to_json }, base_updated_at: block.updated_at.iso8601(6) },
      as: :turbo_stream
    assert_response :success
    assert_equal rich_doc("Hello there"), block.reload.body_document(locale: "en").to_h
  end

  test "a rich_text block's body saves into the form's locale" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0, body: rich_doc("English"))
    patch "#{blocks_path}/#{block.id}", params: { locale: "de", block: { body: rich_doc("Deutsch").to_json }, base_updated_at: block.updated_at.iso8601(6) },
      as: :turbo_stream
    assert_response :success
    stored = block.reload.read_attribute(:body)
    assert_equal rich_doc("Deutsch"), stored["de"]
    assert_equal rich_doc("English"), stored["en"]
  end

  test "an invalid block body answers 422 with the error in the body slot" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    patch "#{blocks_path}/#{block.id}", params: { block: { body: "{broken" }, base_updated_at: block.updated_at.iso8601(6) },
      as: :turbo_stream
    assert_response :unprocessable_entity
    assert_select_in_stream "block-#{block.id}-body-errors", /Body/
  end

  # Fix (final-fixes round, finding 2): the block-card counterpart to
  # `Admin::PostsTest`'s own "removing every speaker" case -- no built-in
  # block type declares a `groups` field, so `test/quote` (`test/support/
  # test_types.rb`) is the one fixture that exercises this for a block's own
  # settings at all.
  test "removing every row of a block's own groups field saves it as empty" do
    with_test_types do
      block = @page.content_blocks.create!(block_type: "test/quote", position: 0,
        settings: { "speakers" => [ { "name" => "Ada" } ] }, translated_settings: { "en" => { "text" => "Hello" } })
      assert_equal %w[Ada], block.settings_object.group(:speakers).map(&:name)

      patch "#{blocks_path}/#{block.id}",
        params: { block: { groups_present: [ "speakers" ] }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
      assert_response :success
      assert_equal [], block.reload.settings_object.group(:speakers).map(&:name)
    end
  end

  test "updating a deleted block answers gone" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    block.destroy!
    patch "#{blocks_path}/#{block.id}", params: { block: { body: rich_doc("x").to_json } }, as: :turbo_stream
    assert_response :gone
    assert_includes response.body, "This block was deleted"
  end

  test "an unavailable block type renders a card with delete only" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    block.update_column(:block_type, "gone/thing")
    get "/cs-studio/pages/#{@page.id}"
    assert_includes response.body, "Unavailable type — gone/thing"
  end

  # Task 12's b5: the one action an unavailable card has works end to end --
  # the block is deleted although its type is no longer registered, and the
  # page's other blocks stay.
  test "an unavailable block can be deleted" do
    keep = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    gone = @page.content_blocks.create!(block_type: "rich_text", position: 1)
    gone.update_column(:block_type, "gone/thing")

    assert_difference -> { @page.content_blocks.count }, -1 do
      delete "#{blocks_path}/#{gone.id}", as: :turbo_stream
    end
    assert_response :success
    assert_not ContentBlock.exists?(gone.id)
    assert ContentBlock.exists?(keep.id)
  end

  # Media library Task 4: an image block's image is a library asset, so a
  # duplicate points at the same asset -- nothing is copied, and the asset
  # can't be deleted while either block uses it (the FK restricts), which
  # is what the old "independent blob" copy (fix round 1) was protecting.
  test "duplicating an image block shares the library asset" do
    source = image_block_with_image

    assert_no_difference "Media::Asset.count" do
      post "#{blocks_path}/#{source.id}/duplicate", as: :turbo_stream
    end
    assert_response :success

    copy = @page.content_blocks.order(:position).last
    assert_not_equal source.id, copy.id
    assert_equal source.media_asset, copy.media_asset

    source.destroy!
    assert copy.reload.media_asset.file.attached?
  end

  # Final fix wave (Minor 6): the copy's image is set inside
  # `ContentBlocks::Save`, so the `block.created` event's snapshot has it --
  # as `media_asset_id` since media library Task 4.
  test "duplicating an image block records block.created with the image in its snapshot" do
    source = image_block_with_image

    post "#{blocks_path}/#{source.id}/duplicate", as: :turbo_stream
    assert_response :success

    copy = @page.content_blocks.order(:position).last
    event = Audit::Event.find_by!(action: "block.created", subject: copy)
    assert_equal source.media_asset_id, event.snapshot["media_asset_id"]
    assert_not event.snapshot.key?("image")
  end

  # Duplicating copies every locale's JSON body document verbatim (the
  # ActionText-era version of this test guarded against a re-rendered
  # `trix-content` wrapper nesting itself on every duplicate; a JSON
  # document is copied as data, so the same guarantee is "byte-for-byte
  # equal, even duplicated twice").
  test "duplicating a rich_text block copies every locale's body document, even duplicated twice" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0, body: rich_doc("Hi **there**"))
    block.assign_body(rich_doc("Hallo"), locale: "de")
    block.save!
    original = block.reload.read_attribute(:body)

    post "#{blocks_path}/#{block.id}/duplicate", as: :turbo_stream
    assert_response :success
    copy = @page.content_blocks.order(:position).last
    assert_equal original, copy.read_attribute(:body)

    post "#{blocks_path}/#{copy.id}/duplicate", as: :turbo_stream
    assert_response :success
    copy2 = @page.content_blocks.order(:position).last
    assert_equal original, copy2.read_attribute(:body)
  end

  # The image column is a library image field (media library Task 8):
  # labelled "Image" (never the page's "Hero image"), a hidden
  # `media_asset_id` the card's autosave sends, and the image's own default
  # alt/caption as the per-use overrides' placeholders.
  test "an image block's card shows the picker field and the image's defaults as the overrides' placeholders" do
    block = image_block_with_image
    block.media_asset.update!(alt: "A dog", caption: "Our dog")
    prefix = Admin::BlockCardComponent.error_prefix(block)

    get "/cs-studio/pages/#{@page.id}"
    assert_response :success

    assert_select "##{prefix}-image-section[data-controller='admin--media-field']" do
      assert_select "p", text: "Image"
      assert_select "input[type=hidden][name='block[media_asset_id]'][value='#{block.media_asset_id}']"
      assert_select "button", text: "Change image"
    end
    assert_select "p", text: "Hero image", count: 0
    assert_select "input[name='block[alt]'][placeholder='A dog']"
    assert_select "input[name='block[caption]'][placeholder='Our dog']"
    assert_equal({ "alt" => "#{prefix}-alt", "caption" => "#{prefix}-caption" },
      JSON.parse(css_select("##{prefix}-image-section").first["data-admin--media-field-placeholder-ids-value"]))
  end

  # Every autosave resends the hidden input's stored id -- a no-op.
  test "autosaving another field resends the stored image id and keeps the image" do
    block = image_block_with_image
    asset = block.media_asset

    patch "#{blocks_path}/#{block.id}",
      params: { block: { caption: "A caption", media_asset_id: asset.id.to_s }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success

    block.reload
    assert_equal "A caption", block.caption(locale: :en)
    assert_equal asset, block.media_asset
  end

  test "choosing a library image sets the block's image" do
    block = image_block_with_image
    chosen = create_media_asset(filename: "medium.png")

    assert_no_difference "Media::Asset.count" do
      patch "#{blocks_path}/#{block.id}",
        params: { block: { media_asset_id: chosen.id.to_s }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    end
    assert_response :success

    assert_equal chosen, block.reload.media_asset
    assert Media::Usage.exists?(media_asset: chosen, owner: block, role: "block_image")
  end

  test "an empty image id (Remove) clears a block's image" do
    block = image_block_with_image

    patch "#{blocks_path}/#{block.id}",
      params: { block: { media_asset_id: "" }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success

    assert_nil block.reload.media_asset
  end

  test "an image id naming no asset is refused into the image column's error slot" do
    block = image_block_with_image
    previous = block.media_asset

    patch "#{blocks_path}/#{block.id}",
      params: { block: { media_asset_id: (Media::Asset.maximum(:id) + 1).to_s }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :unprocessable_entity

    assert_includes response.body, %(target="#{Admin::BlockCardComponent.error_prefix(block)}-image-errors")
    assert_includes response.body, "Image doesn&#39;t exist"
    assert_equal previous, block.reload.media_asset

    # Fix round 1 (I2): the field comes back with the stored image and the
    # message inside it.
    section = response.body.index(%(target="#{Admin::BlockCardComponent.error_prefix(block)}-image-section"))
    assert section, "expected a stream replacing the image field"
    field = response.body[section..]
    assert_includes field, %(name="block[media_asset_id]" id="#{Admin::BlockCardComponent.error_prefix(block)}-image" value="#{previous.id}")
    assert_includes field, "Image doesn&#39;t exist"
  end

  # Review Focus 5 for a block: choosing needs `media.upload` on top of the
  # page's edit right.
  test "choosing a block image without media.upload is a 403 and changes nothing" do
    block = image_block_with_image
    stored = block.media_asset
    chosen = create_media_asset(filename: "medium.png")
    group = access_control_groups(:branch_editors)
    %w[pages.read pages.edit pages.publish].each { |key| AccessControl::Grant.create!(group: group, permission: key, scope: {}) }
    sign_in_as(users(:editor_branch))

    patch "#{blocks_path}/#{block.id}",
      params: { block: { media_asset_id: chosen.id.to_s }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :forbidden

    assert_equal stored, block.reload.media_asset
    assert_equal "media.upload", Audit::Event.where(action: "access.denied").last.metadata["permission"]
    assert_includes response.body, %(target="#{Admin::BlockCardComponent.error_prefix(block)}-image-section")
  end

  # Final fix wave (T6), pinning the Task 6 ruling: a duplicate chooses its
  # image again (through `ContentBlocks::Save`), so copying an image block
  # needs `media.upload` too -- the page's edit right alone is refused, and
  # no copy is made.
  test "duplicating an image block needs media.upload" do
    source = image_block_with_image
    group = access_control_groups(:branch_editors)
    %w[pages.read pages.edit pages.publish].each { |key| AccessControl::Grant.create!(group: group, permission: key, scope: {}) }
    sign_in_as(users(:editor_branch))

    assert_no_difference -> { @page.content_blocks.count } do
      post "#{blocks_path}/#{source.id}/duplicate", as: :turbo_stream
    end
    assert_response :forbidden
    assert_equal "media.upload", Audit::Event.where(action: "access.denied").last.metadata["permission"]
  end

  # Only a type that `uses :image` takes an image id at all.
  test "a media_asset_id sent to a block type without an image is ignored" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)

    patch "#{blocks_path}/#{block.id}",
      params: { block: { media_asset_id: create_media_asset.id.to_s }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success

    assert_nil block.reload.media_asset_id
  end

  # The interim upload field (media library Task 4) is gone.
  test "an image file param is ignored and uploads nothing" do
    block = image_block_with_image
    previous = block.media_asset

    assert_no_difference "Media::Asset.count" do
      patch "#{blocks_path}/#{block.id}",
        params: { block: { image: fixture_file_upload("medium.png", "image/png") }, base_updated_at: block.updated_at.iso8601(6) },
        as: :turbo_stream
    end
    assert_response :success
    assert_equal previous, block.reload.media_asset
  end

  private

  def image_block_with_image
    @page.content_blocks.create!(block_type: "image", position: 0, media_asset: create_media_asset)
  end
  # Final fix wave I3: a block write touches its page, so a block response
  # also hands the page settings form on the same screen the page's fresh
  # `updated_at` -- but only when the base that form holds (sent along as
  # `X-Page-Base-Updated-At`) was still current before this write;
  # otherwise its next autosave would report "Changed elsewhere" against
  # nothing but this same editor.
  test "block writes refresh the page form's base so its next save isn't stale" do
    block = @page.content_blocks.create!(block_type: :rich_text, position: 0)
    travel 1.minute

    patch "#{blocks_path}/#{block.id}", params: { block: { body: rich_doc("Edited").to_json }, base_updated_at: block.updated_at.iso8601(6) },
      headers: page_base_header(@page.reload.updated_at), as: :turbo_stream
    assert_response :success
    fresh = @page.reload.updated_at.iso8601(6)
    assert_equal fresh, streamed_page_base

    patch "/cs-studio/pages/#{@page.id}", params: { page: { title: "About us" }, base_updated_at: fresh }, as: :turbo_stream
    assert_response :success
    assert_no_match(/CHANGED ELSEWHERE|changed-elsewhere/, response.body)

    travel 1.minute
    patch "#{blocks_path}/reorder", params: { ids: [ block.id ] }, headers: page_base_header(@page.reload.updated_at), as: :turbo_stream
    assert_response :success
    delete "#{blocks_path}/#{block.id}", headers: page_base_header(@page.reload.updated_at), as: :turbo_stream
    assert_response :success
    assert_equal @page.reload.updated_at.iso8601(6), streamed_page_base
  end

  test "a block save made on a stale base is refused, names who changed it, and keeps the newer text" do
    block = @page.content_blocks.create!(block_type: :image, position: 0)
    stale = block.updated_at.iso8601(6)
    travel 1.minute
    as(users(:two), channel: :admin) { ContentBlocks::Save.call(block, translations: { "en" => { caption: "Changed by someone else" } }) }

    patch "#{blocks_path}/#{block.id}", params: { block: { caption: "My stale edit" }, base_updated_at: stale }, as: :turbo_stream
    assert_response :conflict
    assert_equal "Changed by someone else", block.reload.caption
    assert_select_in_stream "block-#{block.id}-save-status", /CHANGED ELSEWHERE/
    assert_select_in_stream "editor-notice", /Changed by .+Reload/m
    assert_no_match(/block-#{block.id}-base-updated-at/, response.body)
    assert_no_match(/page-base-updated-at/, response.body, "a refused save vouches for nothing")
  end

  test "a block save on a current base still saves" do
    block = @page.content_blocks.create!(block_type: :image, position: 0)
    patch "#{blocks_path}/#{block.id}", params: { block: { caption: "Fresh" }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_equal "Fresh", block.reload.caption
  end

  # The same rule as the page hero's (`MediaFields#without_untouched_media_slot`),
  # for an image block: a later save of the block that does not touch its image
  # leaves the refusal message in place; choosing or clearing the image clears it.
  test "a refused image choice's message survives a later save that leaves the image alone" do
    block = @page.content_blocks.create!(block_type: :image, position: 0)
    slot = "block-#{block.id}-image-errors"
    gone = Media::Asset.maximum(:id).to_i + 1000

    patch "#{blocks_path}/#{block.id}", params: { block: { media_asset_id: gone.to_s }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_match(/doesn.*t exist/, response.body)

    patch "#{blocks_path}/#{block.id}", params: { block: { caption: "Later", media_asset_id: "" }, base_updated_at: block.reload.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_nil Nokogiri::HTML5.fragment(response.body).css("turbo-stream[target='#{slot}']").find { |stream| stream.at_css("template").text.strip.present? },
      "the refusal message must not be rewritten by a save that left the image alone"
    assert Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[target='#{slot}']").nil?, "its slot is not even touched"

    chosen = create_media_asset
    patch "#{blocks_path}/#{block.id}", params: { block: { media_asset_id: chosen.id.to_s }, base_updated_at: block.reload.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[target='#{slot}']"), "choosing an image is acting on the field: its slot is rewritten"
  end

  test "a block on a live page saves 'to site', like the page does; on a draft page it just saves" do
    block = @page.content_blocks.create!(block_type: :image, position: 0)
    assert @page.live?
    patch "#{blocks_path}/#{block.id}", params: { block: { caption: "Live" }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_select_in_stream "block-#{block.id}-save-status", /● SAVED TO SITE \d\d:\d\d/

    draft = create_page(title: "Draft page", published: false)
    draft_block = draft.content_blocks.create!(block_type: :image, position: 0)
    patch "/cs-studio/pages/#{draft.id}/content_blocks/#{draft_block.id}", params: { block: { caption: "Draft" }, base_updated_at: draft_block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_select_in_stream "block-#{draft_block.id}-save-status", /\ASAVED \d\d:\d\d/
  end

  # Fix round 2: the refresh above must never paper over a real conflict.
  # A loaded the editor, B then saved the page's settings, then A edited a
  # block: A's page form still holds the pre-B base, so the block response
  # must leave it alone -- A's next page autosave is then reported as
  # "Changed elsewhere", as it would have been without the block edit.
  test "a block edit doesn't hide a page save made elsewhere in the meantime" do
    block = @page.content_blocks.create!(block_type: :rich_text, position: 0)
    a_base = @page.reload.updated_at
    travel 1.minute
    assert Current.set(actor: users(:two), channel: :admin) { Pages::Save.call(@page.reload, translations: { Locales.default => { title: "B's title" } }) }.ok?
    travel 1.minute

    patch "#{blocks_path}/#{block.id}", params: { block: { body: rich_doc("A's edit").to_json }, base_updated_at: block.reload.updated_at.iso8601(6) },
      headers: page_base_header(a_base), as: :turbo_stream
    assert_response :success
    assert_nil Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[target='page-base-updated-at']")

    patch "/cs-studio/pages/#{@page.id}", params: { page: { subtitle: "A's subtitle" }, base_updated_at: a_base.iso8601(6) }, as: :turbo_stream
    assert_response :conflict
    assert_match(/CHANGED ELSEWHERE/, response.body)
    assert_select_in_stream "editor-notice", /Changed by two@example\.com/
    assert_nil @page.reload.subtitle
    assert_equal "B's title", @page.title
  end

  # No page base sent (a client that doesn't send one): nothing to vouch
  # for, so the page form's base is never moved.
  test "a block write without the page form's base doesn't stream one" do
    block = @page.content_blocks.create!(block_type: :rich_text, position: 0)

    patch "#{blocks_path}/#{block.id}", params: { block: { body: rich_doc("Edited").to_json }, base_updated_at: block.updated_at.iso8601(6) },
      as: :turbo_stream
    assert_response :success
    assert_nil Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[target='page-base-updated-at']")
  end

  def page_base_header(time) = { "X-Page-Base-Updated-At" => time.iso8601(6) }

  def streamed_page_base
    stream = Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[target='page-base-updated-at']")
    assert stream, "expected the page form's base in:\n#{response.body}"
    stream.inner_html[/value="([^"]+)"/, 1]
  end

  # Task 7: a translation tab's block form no longer renders the untranslated
  # settings as inputs (they are read-only under "Shared fields"), so its
  # autosave sends exactly the keys below -- and the shared values must be
  # exactly what they were.
  test "a translation-tab save of a block leaves its shared settings untouched" do
    with_test_types do
      block = ContentBlocks::Save.call(@page.content_blocks.new, attributes: { block_type: "test/quote", settings: { cite: "https://example.com/a" } },
        translations: { "en" => { settings: { text: "To be" } } }).record
      assert block.persisted?

      get "/cs-studio/pages/#{@page.id}", params: { locale: "de" }
      assert_select "form.admin-translation-form input[name='block[settings][text]']"
      assert_select "form.admin-translation-form input[name='block[settings][cite]']", count: 0

      patch "/cs-studio/pages/#{@page.id}/content_blocks/#{block.id}",
        params: { locale: "de", block: { settings: { text: "Sein" } }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream

      assert_response :success
      block.reload
      assert_equal "https://example.com/a", block.settings["cite"]
      assert_equal "Sein", block.settings_object(locale: :de).text
      assert_equal "To be", block.settings_object(locale: Locales.default).text
    end
  end

  test "a translation-tab save of a post_list block (a form with no inputs but the base) leaves its settings untouched" do
    block = ContentBlocks::Save.call(@page.content_blocks.new, attributes: { block_type: "post_list", settings: { content_type: "blog", limit: 3 } }).record

    patch "/cs-studio/pages/#{@page.id}/content_blocks/#{block.id}",
      params: { locale: "de", base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream

    block.reload
    assert_equal 3, block.settings["limit"]
    assert_equal "blog", block.settings["content_type"]
    assert_not block.translated_settings.key?("de")
  end

  test "duplicating a section streams one card holding the copies of its blocks" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)

    assert_difference -> { @page.content_blocks.count }, 2 do
      post "#{blocks_path}/#{section.id}/duplicate", as: :turbo_stream
    end
    assert_response :created
    copy = @page.content_blocks.top_level.reorder(:position).last
    assert_includes response.body, "section-#{copy.id}-lane-1"
    assert_includes response.body, "block-#{copy.section_blocks.sole.id}-panel"
  end

  test "a reorder that names a column moves the block and a stale one is a 422" do
    section = @page.content_blocks.create!(block_type: "section", position: 0)
    block = @page.content_blocks.create!(block_type: "rich_text", position: 1)

    patch "#{blocks_path}/reorder", params: { ids: [ block.id ], section_id: section.id, column: 2, moved_from: { block.id => { section_id: "", column: "" } } }, as: :turbo_stream
    assert_response :success
    assert_equal [ section.id, 2 ], block.reload.then { |b| [ b.section_id, b.section_column ] }

    patch "#{blocks_path}/reorder", params: { ids: [ block.id ], section_id: section.id, column: 1, moved_from: { block.id => { section_id: "", column: "" } } }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_includes response.body, ContentBlocks::Reorder::STALE
  end

  # Sections plan, Q5: the Undo toast restores the page's own order, which
  # can't undo a move between containers.
  test "a move between containers offers no Undo, and one inside a column neither" do
    section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    first = @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
    second = @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 1)

    patch "#{blocks_path}/reorder", params: { ids: [ second.id, first.id ], section_id: section.id, column: 1 }, as: :turbo_stream
    assert_response :success
    assert_not_includes response.body, "Undo"

    patch "#{blocks_path}/reorder", params: { ids: [ section.id, first.id ], moved_from: { first.id => { section_id: section.id, column: 1 } } }, as: :turbo_stream
    assert_response :success
    assert_not_includes response.body, "Undo"
    assert_equal [ section, first ], @page.content_blocks.top_level.reorder(:position).to_a
  end

  test "a moved_from that is no hash is read as none, and a forged entry in one is a 422, never an error" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)

    patch "#{blocks_path}/reorder", params: { ids: [ block.id ], moved_from: "x" }, as: :turbo_stream
    assert_response :success

    patch "#{blocks_path}/reorder", params: { ids: [ block.id ], moved_from: { "0" => "x" } }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_includes response.body, ContentBlocks::Reorder::STALE
  end
end
