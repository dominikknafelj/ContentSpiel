require "test_helper"

# Covers the Page admin beyond "the route renders": the parent picker that
# builds the tree, the hero fields that only a landing page has, and the
# content-block editor embedded in the page form.
#
# All three are assembled out of Avo primitives rather than configured with one
# flag (Avo 4.2.3 Community has no Mobility integration, no client-side
# conditional fields, and the `nested:` option needs the paid avo-nested gem),
# so each one is tested against the real rendered form and the real submit
# path rather than trusting the field declarations to line up.
class AvoPageEditingTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "editor@example.com", password: "password123")
    sign_in_as(@user)

    @root = Page.create!(title: "Home", page_type: :standard)
    @about = Page.create!(title: "About", slug: "about", parent: @root)
  end

  # -- parent picker ---------------------------------------------------------

  test "the parent picker offers the other pages" do
    get "/avo/resources/pages/#{@about.id}/edit"

    assert_response :success
    assert_includes parent_option_values, @root.id.to_s,
      "expected the root page to be offered as a parent"
  end

  # The picker is a plain belongs_to select over the same table, so without a
  # scope a page is offered as its own parent -- which closure_tree would then
  # reject with an exception-flavoured validation error instead of the form
  # never letting it happen.
  test "the parent picker does not offer the page being edited" do
    get "/avo/resources/pages/#{@about.id}/edit"

    assert_response :success
    assert_not_includes parent_option_values, @about.id.to_s,
      "the page being edited must not be offered as its own parent"
  end

  # Hiding the option in the markup is only half of it: the option list is
  # client-side data, so the same scope has to gate what a submitted parent_id
  # is allowed to resolve to.
  test "submitting the page's own id as its parent is turned away" do
    put "/avo/resources/pages/#{@about.id}", params: { page: { parent_id: @about.id } }

    # Avo resolves a submitted association id through the same scope it built
    # the dropdown from, so an id the scope excludes finds no record at all.
    assert_response :not_found

    assert_not_equal @about.id, @about.reload.parent_id,
      "a page must not be able to become its own parent"
    assert_equal @root.id, @about.parent_id
  end

  # -- sibling order ---------------------------------------------------------

  # There is no drag-and-drop (page-tree design spec section 5), so the
  # `position` input is the only way to reorder a branch -- which makes it
  # worth checking that editing it actually moves the page among its siblings
  # rather than just writing a number nothing reads.
  test "a page is moved up among its siblings through the page form" do
    contact = Page.create!(title: "Contact", slug: "contact", parent: @root)
    news = Page.create!(title: "News", slug: "news", parent: @root)
    assert_equal [ @about.id, contact.id, news.id ], @root.children.reload.map(&:id)

    put "/avo/resources/pages/#{news.id}", params: { page: {
      parent_id: @root.id, position: 0
    } }

    assert_response :redirect
    assert_equal [ news.id, @about.id, contact.id ], @root.children.reload.map(&:id)
    assert_equal [ 0, 1, 2 ], @root.children.map(&:position),
      "siblings must be left densely numbered from 0"
  end

  test "a page is moved down among its siblings through the page form" do
    contact = Page.create!(title: "Contact", slug: "contact", parent: @root)
    news = Page.create!(title: "News", slug: "news", parent: @root)

    put "/avo/resources/pages/#{@about.id}", params: { page: {
      parent_id: @root.id, position: 2
    } }

    assert_response :redirect
    assert_equal [ contact.id, news.id, @about.id ], @root.children.reload.map(&:id)
    assert_equal [ 0, 1, 2 ], @root.children.map(&:position)
  end

  # -- conditional hero fields ----------------------------------------------

  # The hero image is a top-level field, so unlike the subtitle (which lives
  # inside tabs the index never renders) its visibility lambda runs once per
  # row on the index -- for a page of either type.
  test "the page index and show pages render for both page types" do
    @about.update!(page_type: :landing)

    get "/avo/resources/pages"
    assert_response :success

    [ @root, @about ].each do |page|
      get "/avo/resources/pages/#{page.id}"
      assert_response :success, "expected the #{page.page_type} page's show view to render"
    end
  end

  test "a standard page's form offers neither subtitle nor hero image" do
    get "/avo/resources/pages/#{@about.id}/edit"

    assert_response :success
    assert_not_includes response.body, %(name="page[hero_image]"),
      "a standard page has no hero image"

    Mobility.available_locales.each do |locale|
      assert_not_includes response.body, %(name="page[subtitle_#{locale}]"),
        "a standard page has no subtitle in #{locale}"
    end
  end

  test "a landing page's form offers the subtitle in every locale and a hero image" do
    @about.update!(page_type: :landing)

    get "/avo/resources/pages/#{@about.id}/edit"

    assert_response :success
    assert_includes response.body, %(name="page[hero_image]"),
      "a landing page has a hero image"

    Mobility.available_locales.each do |locale|
      assert_includes response.body, %(name="page[subtitle_#{locale}]"),
        "a landing page has a subtitle in #{locale}"
    end
  end

  test "a landing page's subtitle is written per locale" do
    @about.update!(page_type: :landing)

    put "/avo/resources/pages/#{@about.id}", params: { page: {
      page_type: "landing", subtitle_en: "Who we are", subtitle_de: "Wer wir sind"
    } }

    assert_response :redirect

    saved = Page.find(@about.id)
    assert_equal "Who we are", saved.subtitle_en
    assert_equal "Wer wir sind", saved.subtitle_de
  end

  # -- translated fields -----------------------------------------------------

  test "the page form exposes a separate input per locale for every translated field" do
    get "/avo/resources/pages/#{@about.id}/edit"

    assert_response :success

    Mobility.available_locales.each do |locale|
      %w[title slug meta_title meta_description].each do |attribute|
        assert_includes response.body, %(name="page[#{attribute}_#{locale}]"),
          "expected an input for #{attribute} in #{locale}"
      end
    end
  end

  # -- nested content blocks -------------------------------------------------

  test "the page form renders a nested row per content block plus a blank one to add with" do
    @about.content_blocks.create!(block_type: :rich_text, position: 0)

    get "/avo/resources/pages/#{@about.id}/edit"

    assert_response :success
    assert_includes response.body, %(name="page[content_blocks_attributes][0][block_type]"),
      "expected a nested row for the existing block"
    assert_includes response.body, %(name="page[content_blocks_attributes][1][block_type]"),
      "expected a blank nested row to add a block with"
  end

  test "the nested block row exposes the type-specific and translated fields" do
    @about.content_blocks.create!(block_type: :image, position: 0)

    get "/avo/resources/pages/#{@about.id}/edit"

    assert_response :success

    assert_includes response.body, %(name="page[content_blocks_attributes][0][position]")
    assert_includes response.body, %(name="page[content_blocks_attributes][0][image]")
    assert_includes response.body, %(name="page[content_blocks_attributes][0][settings][content_type]")
    assert_includes response.body, %(name="page[content_blocks_attributes][0][_destroy]")

    Mobility.available_locales.each do |locale|
      assert_includes response.body, %(name="page[content_blocks_attributes][0][caption_#{locale}]")
      assert_includes response.body, %(name="page[content_blocks_attributes][0][body_#{locale}]")
    end
  end

  test "a content block is added through the page form" do
    assert_difference -> { @about.content_blocks.count }, 1 do
      put "/avo/resources/pages/#{@about.id}", params: { page: {
        content_blocks_attributes: {
          "0" => { block_type: "rich_text", position: "0", body_en: "<p>Hello</p>" }
        }
      } }
    end

    assert_response :redirect

    block = @about.content_blocks.reload.first
    assert block.rich_text?
    assert_equal "Hello", block.body_en.to_plain_text.strip
  end

  # The blank row rides along on every save, so it must not save itself as an
  # empty block each time the page is edited.
  test "the blank nested row is not saved as an empty block" do
    assert_no_difference -> { @about.content_blocks.count } do
      put "/avo/resources/pages/#{@about.id}", params: { page: {
        title_en: "About us",
        content_blocks_attributes: {
          "0" => { block_type: "", position: "", body_en: "", settings: { content_type: "" } }
        }
      } }
    end

    assert_response :redirect
    assert_equal "About us", Page.find(@about.id).title_en
  end

  test "content blocks are reordered through the page form" do
    first = @about.content_blocks.create!(block_type: :rich_text, position: 0)
    second = @about.content_blocks.create!(block_type: :image, position: 1)

    put "/avo/resources/pages/#{@about.id}", params: { page: {
      content_blocks_attributes: {
        "0" => { id: first.id, block_type: "rich_text", position: "1" },
        "1" => { id: second.id, block_type: "image", position: "0" }
      }
    } }

    assert_response :redirect
    assert_equal [ second.id, first.id ], @about.content_blocks.reload.map(&:id)
  end

  test "a content block is removed through the page form" do
    kept = @about.content_blocks.create!(block_type: :rich_text, position: 0)
    removed = @about.content_blocks.create!(block_type: :image, position: 1)

    assert_difference -> { ContentBlock.count }, -1 do
      put "/avo/resources/pages/#{@about.id}", params: { page: {
        content_blocks_attributes: {
          "0" => { id: kept.id, block_type: "rich_text", position: "0" },
          "1" => { id: removed.id, block_type: "image", position: "1", _destroy: "1" }
        }
      } }
    end

    assert_response :redirect
    assert_equal [ kept.id ], @about.content_blocks.reload.map(&:id)
  end

  test "a post_list block's settings are written from the nested row" do
    put "/avo/resources/pages/#{@about.id}", params: { page: {
      content_blocks_attributes: {
        "0" => { block_type: "post_list", position: "0",
                 settings: { content_type: "blog", tag: "rails", limit: "5" } }
      }
    } }

    assert_response :redirect

    block = @about.content_blocks.reload.first
    assert block.post_list?
    assert_equal({ "content_type" => "blog", "tag" => "rails", "limit" => "5" }, block.settings)
  end

  # Every block's row carries the same settings inputs, so a rich_text block
  # submits three blank ones -- which must not end up stored as empty strings
  # that the post_list renderer would then query with.
  test "blank settings are not stored on a block that has none" do
    put "/avo/resources/pages/#{@about.id}", params: { page: {
      content_blocks_attributes: {
        "0" => { block_type: "rich_text", position: "0",
                 settings: { content_type: "", tag: "", limit: "" } }
      }
    } }

    assert_response :redirect
    assert_equal({}, @about.content_blocks.reload.first.settings)
  end

  # The blank row arrives pre-filled with the next free position, so the editor
  # only has to pick a type.
  test "the blank nested row is pre-filled with the next position" do
    @about.content_blocks.create!(block_type: :rich_text, position: 0)

    get "/avo/resources/pages/#{@about.id}/edit"

    assert_response :success
    assert_match(/<input[^>]*value="1"[^>]*name="page\[content_blocks_attributes\]\[1\]\[position\]"|<input[^>]*name="page\[content_blocks_attributes\]\[1\]\[position\]"[^>]*value="1"/,
      response.body, "expected the blank row's position to default to 1")
  end

  # `position` is NOT NULL with a database default, so a cleared input reaches
  # Postgres as nil and comes back as a raw not-null violation rendered into
  # the page unless the model validates it first.
  test "a cleared position comes back as a form error rather than a Postgres error" do
    put "/avo/resources/pages/#{@about.id}", params: { page: {
      content_blocks_attributes: { "0" => { block_type: "rich_text", position: "" } }
    } }

    assert_response :unprocessable_entity
    assert_no_match(/violates not-null constraint/, response.body,
      "a blank position must surface as a validation error, not a raw Postgres error")
    assert_equal 0, @about.content_blocks.reload.count
  end

  test "a content block that fails validation comes back as a form error" do
    put "/avo/resources/pages/#{@about.id}", params: { page: {
      content_blocks_attributes: {
        "0" => { block_type: "post_list", position: "0",
                 settings: { content_type: "not-a-content-type" } }
      }
    } }

    assert_response :unprocessable_entity
    assert_equal 0, @about.content_blocks.reload.count
  end

  private
    # The `value`s of the `<option>`s inside the parent picker's select.
    def parent_option_values
      select = response.body[/<select[^>]*name="page\[parent_id\]".*?<\/select>/m]
      assert select, "expected a parent picker select on the page form"

      select.scan(/<option[^>]*value="([^"]*)"/).flatten
    end
end
