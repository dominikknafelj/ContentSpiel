require "test_helper"

# A Form block on a public page (forms plan, Task 7; spec "Sending" and its
# anti-goals): the page stays one cookie-less, cacheable answer for every
# visitor, the form posts to its own endpoint with no token of this
# application, and what the form draws follows its Save (a form has no
# published copy) and the site's encryption keys.
class PublicFormBlockTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @form = forms(:contact)
    @page = create_page(title: "Contact us")
  end

  def add_form(form = @form, page: @page, **attributes)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "form", settings: { "form_id" => form.id.to_s } }.merge(attributes))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def path = PublicSite::Urls.new.path_for(@page.reload, "en")

  test "a page with a Form block answers 200, cacheable, with no Set-Cookie, under both themes" do
    block = add_form
    publish_changes(@page)

    [ ->(&run) { run.call }, ->(&run) { with_plain_theme(&run) } ].each do |theme|
      theme.call { get path }

      assert_response :success
      assert_equal "max-age=0, public, must-revalidate", response.headers["Cache-Control"]
      assert_nil response.headers["Set-Cookie"], "a public page sets no cookie"
      assert response.headers["ETag"].present?
      assert_select "form.content-block--form[method=post][action='/forms/#{@form.id}']" do
        assert_select "input[name='answers[f_name0001]']#form-#{block.id}-f_name0001"
        assert_select "input[name=page_id][value='#{@page.id}']"
      end
    end
  end

  test "the form posts to the endpoint with no token of this application and sets no cookie" do
    add_form
    publish_changes(@page)
    ActionController::Base.allow_forgery_protection = true

    get path

    assert_response :success
    assert_select "form.content-block--form" do
      assert_select "input[name=authenticity_token]", count: 0
      assert_select "input[name=_method]", count: 0
    end
    assert_select "meta[name=csrf-token]", count: 0
    assert_nil response.headers["Set-Cookie"]
    assert_equal "/forms/#{@form.id}", css_select("form.content-block--form").first["action"]
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "changing the form moves the page's ETag; trashing it draws nothing on the next request" do
    add_form
    publish_changes(@page)
    get path
    etag = response.headers["ETag"]
    get path, headers: { "If-None-Match" => etag }
    assert_response :not_modified

    fields = @form.read_attribute(:fields).map { |field| field.symbolize_keys }
    fields[0][:label] = { "en" => "Full name" }
    result = Current.set(actor: users(:one), channel: :admin) do
      Forms::Save.call(@form, attributes: { name: "Contact" }, fields: fields,
        destinations: @form.destinations.map { |destination| { id: destination.id, kind: destination.kind, settings: destination.settings, secrets: {} } })
    end
    assert result.ok?, result.errors.to_sentence

    get path, headers: { "If-None-Match" => etag }
    assert_response :success, "a form's Save is what the page draws: its ETag moves"
    assert_select "label", text: /Full name/
    etag = response.headers["ETag"]

    assert Current.set(actor: users(:one), channel: :admin) { Trash::Move.call(@form.reload) }.ok?
    get path, headers: { "If-None-Match" => etag }
    assert_response :success
    assert_select "form.content-block--form", count: 0
    assert_select ".content-block--form", count: 0
  end

  test "the page's ETag follows the site's encryption keys, which decide whether the form takes answers" do
    add_form
    publish_changes(@page)
    get path
    etag = response.headers["ETag"]

    without_encryption_keys { get path, headers: { "If-None-Match" => etag } }
    assert_response :success, "a site that lost its keys is told so, never a 304 of the form that took answers"
    assert_select "form.content-block--form .form-unavailable", text: I18n.t("public.forms.unavailable")
    assert_select "form.content-block--form fieldset[disabled]"
  end

  test "a Form block in a section, in each column" do
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "two" } })
    assert section.ok?, section.errors.to_sentence
    first = add_form(section_id: section.record.id, section_column: 1)
    second = add_form(forms(:newsletter), section_id: section.record.id, section_column: 2)
    publish_changes(@page)

    get path

    assert_response :success
    columns = css_select(".content-section__column")
    assert_equal 2, columns.size
    assert_equal 1, columns[0].css("form.content-block--form input#form-#{first.id}-f_name0001").size
    assert_equal 1, columns[1].css("form.content-block--form input#form-#{second.id}-f_mail0002").size
    assert_select "form.content-block--form", count: 2
  end

  test "a Form block is drawn from the page's published copy: one added and not published is not on the page" do
    add_form
    get path

    assert_response :success
    assert_select "form.content-block--form", count: 0
  end
end
