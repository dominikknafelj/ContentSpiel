require "application_system_test_case"

# The Form block on the public site, in a browser (forms plan, Task 7;
# design.md 4): sent in place by `form-send` with errors beside their
# fields and a thank-you where the form stood, and without the script a
# plain post that lands on the endpoint's own page.
#
# The draw token is aged in the page (`aged_drawn`, test/support/form_sends.rb)
# rather than waited out: a send under three seconds after the draw is taken
# for a script's and dropped, and the sleeps guard refuses a wait.
class FormBlockSystemTest < ApplicationSystemTestCase
  FORM = "form.content-block--form".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    clear_form_send_limits
    @form = forms(:contact)
    @page = create_page(title: "Contact us")
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "form", settings: { "form_id" => @form.id.to_s } })
    assert result.ok?, result.errors.to_sentence
    @block = result.record
    publish_changes(@page)
  end

  CONNECTED = "(() => { const form = document.querySelector('#{FORM}'); return Boolean(window.Stimulus && form && window.Stimulus.getControllerForElementAndIdentifier(form, 'form-send')) })()".freeze

  def open_page
    visit PublicSite::Urls.new.path_for(@page, "en")
    await_js(CONNECTED)
    age_token
  end

  def age_token = page.execute_script("document.querySelector('#{FORM} input[name=drawn]').value = arguments[0]", aged_drawn(@form))

  def id_of(key) = "form-#{@block.id}-#{key}"

  def focused_id = page.evaluate_script("document.activeElement && document.activeElement.id")

  def focused_role = page.evaluate_script("document.activeElement && document.activeElement.getAttribute('role')")

  test "with JavaScript a send shows the thank-you in place and focuses it" do
    open_page
    fill_in "Your name", with: "Ada"
    fill_in "Email address", with: "ada@example.com"
    fill_in "Message", with: "Hello"

    assert_difference -> { Forms::Submission.count }, 1 do
      click_button "Send"
      assert_selector "#{FORM} [data-form-send-target=done][role=status]", text: "Thank you, we'll be in touch."
    end
    assert_equal "status", focused_role, "the focus is on the thank-you"
    assert_no_selector "#{FORM} [data-form-send-target=body]"
    assert_no_selector "#{FORM} [data-form-send-target=summary]"
    assert_equal PublicSite::Urls.new.path_for(@page, "en"), page.current_path, "the visitor stayed on the page"
  end

  test "errors appear beside their fields, the summary is focused and links to them, and the typed values stay" do
    open_page
    # The browser's own check would stop an empty required field first:
    # this is the server's answer, as for a rule the browser does not know.
    page.execute_script("document.querySelector('#{FORM}').noValidate = true")
    fill_in "Email address", with: "ada@example.com"
    fill_in "Message", with: "Kept"
    click_button "Send"

    assert_selector "#{FORM} [role=alert]", text: "Please correct 1 answer."
    assert_equal "alert", focused_role, "the summary takes the focus"
    assert_selector "##{id_of("f_name0001")}-error", text: "Please fill in this field."
    name = find("##{id_of("f_name0001")}")
    assert_equal "true", name["aria-invalid"]
    assert_includes name["aria-describedby"].split, "#{id_of("f_name0001")}-error"
    assert_equal "ada@example.com", find_field("Email address").value
    assert_equal "Kept", find_field("Message").value
    assert_nil find("##{id_of("f_mail0001")}")["aria-invalid"]

    link = find("#{FORM} [role=alert] a", text: "Your name: Please fill in this field.")
    assert_equal "##{id_of("f_name0001")}", link["href"].sub(/\A.*(?=#)/, "")
    link.click
    assert_equal id_of("f_name0001"), focused_id, "the link moves the focus to its field"

    # Corrected and sent again: the errors go, the thank-you comes.
    fill_in "Your name", with: "Ada"
    click_button "Send"
    assert_selector "#{FORM} [data-form-send-target=done]", text: "Thank you, we'll be in touch."
    assert_no_selector "##{id_of("f_name0001")}-error"
  end

  test "with no answer the summary says so, the answers stay and the browser sends nothing itself" do
    open_page
    page.execute_script("window.fetch = () => Promise.reject(new TypeError('offline'))")
    fill_in "Your name", with: "Ada"
    fill_in "Email address", with: "ada@example.com"

    assert_no_difference -> { Forms::Submission.count } do
      click_button "Send"
      assert_selector "#{FORM} [role=alert][data-notice]", text: I18n.t("public.forms.network")
    end
    assert_equal "Ada", find_field("Your name").value
    assert_equal PublicSite::Urls.new.path_for(@page, "en"), page.current_path
    assert_selector "#{FORM} button[type=submit]:not([disabled])", text: "Send"
  end

  # A PAGE THAT STAYS. Turbo copies the page it is on, firing
  # `turbo:before-cache`, when the browser itself goes to an anchor in it
  # (`historyPoppedWithEmptyState`: a link Turbo does not drive, a typed
  # fragment, Back between two anchors). The script takes nothing back
  # there, or the thank-you and the errors would vanish under a visitor who
  # never left (the Code block's incident, test/system/code_block_test.rb).
  # A link Turbo drives draws the page again from the server, which is a new
  # form and no case of this script's.
  def add_anchor
    page.execute_script(<<~JS)
      const main = document.querySelector("main")
      main.insertAdjacentHTML("afterbegin", '<a id="jump" href="#further-down" data-turbo="false">Jump</a>')
      main.insertAdjacentHTML("beforeend", '<h2 id="further-down">Further down</h2>')
      window.__caches = 0
      document.addEventListener("turbo:before-cache", () => { window.__caches += 1 })
    JS
  end

  def follow_anchor
    find("a#jump").click
    await_js("window.__caches > 0 && location.hash === '#further-down'")
    await_frames
    assert page.evaluate_script("document.getElementById('jump') !== null"), "the page stayed: it was not drawn again"
  end

  test "after a send, following an anchor of the page leaves the thank-you where it is" do
    open_page
    add_anchor
    fill_in "Your name", with: "Ada"
    fill_in "Email address", with: "ada@example.com"
    click_button "Send"
    assert_selector "#{FORM} [data-form-send-target=done]", text: "Thank you, we'll be in touch."

    follow_anchor

    assert_selector "#{FORM} [data-form-send-target=done]", text: "Thank you, we'll be in touch."
    assert_no_selector "#{FORM} [data-form-send-target=body]"
  end

  test "after errors, following an anchor of the page leaves the errors and the summary where they are" do
    open_page
    add_anchor
    page.execute_script("document.querySelector('#{FORM}').noValidate = true")
    fill_in "Email address", with: "ada@example.com"
    click_button "Send"
    assert_selector "#{FORM} [role=alert]", text: "Please correct 1 answer."

    follow_anchor

    assert_selector "#{FORM} [role=alert]", text: "Please correct 1 answer."
    assert_selector "##{id_of("f_name0001")}-error", text: "Please fill in this field."
    assert_equal "true", find("##{id_of("f_name0001")}")["aria-invalid"]
    assert_equal "ada@example.com", find_field("Email address").value
  end

  test "an answer for a field the page does not know is an item of the summary with no link, so the list says as many as the line" do
    open_page
    page.execute_script(<<~JS)
      window.fetch = () => Promise.resolve(new Response(JSON.stringify({ status: "invalid", summary: "Please correct 2 answers.",
        errors: [ { key: "f_name0001", message: "Please fill in this field.", item: "Your name: Please fill in this field." },
                  { key: "f_gone0001", message: "Please check this entry.", item: "Old field: Please check this entry." } ] }),
        { status: 422, headers: { "Content-Type": "application/json" } }))
    JS
    fill_in "Your name", with: "Ada"
    fill_in "Email address", with: "ada@example.com"
    click_button "Send"

    assert_selector "#{FORM} [role=alert] li", count: 2
    assert_selector "#{FORM} [role=alert] li a", count: 1, text: "Your name: Please fill in this field."
    assert_selector "#{FORM} [role=alert] li", text: "Old field: Please check this entry."
  end

  test "a page left and come back to by Back shows the form as drawn, nothing written left in it" do
    open_page
    page.execute_script("document.querySelector('#{FORM}').noValidate = true")
    click_button "Send"
    assert_selector "#{FORM} [role=alert]", text: "Please correct 2 answers."

    find("header a[href='/']", match: :first).click
    assert_no_selector FORM
    page.go_back
    await_js(CONNECTED)

    assert_no_selector "#{FORM} [role=alert]"
    assert_equal "", page.evaluate_script("document.querySelector('#{FORM} [role=alert]').textContent")
    assert_no_selector "#{FORM} [aria-invalid]", visible: :all
    assert_no_selector "#{FORM} .form-field__error", visible: true
    assert_selector "#{FORM} button[type=submit]", text: "Send"
    assert_no_selector "#{FORM} [data-form-send-target=done]"
  end

  test "without JavaScript (the script not registered) the send lands on the plain thank-you page with a link back" do
    open_page
    page.execute_script("const form = document.querySelector('#{FORM}'); form.removeAttribute('data-controller'); form.removeAttribute('data-action')")
    await_js("!window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('#{FORM}'), 'form-send')")
    fill_in "Your name", with: "Ada"
    fill_in "Email address", with: "ada@example.com"
    click_button "Send"

    assert_selector "h1", text: "Sent"
    assert_selector "[role=status]", text: "Thank you, we'll be in touch."
    assert_selector "a[href='#{PublicSite::Urls.new.path_for(@page, "en")}']", text: "← Back to the page"
    assert_equal "/forms/#{@form.id}", page.current_path
  end
end
