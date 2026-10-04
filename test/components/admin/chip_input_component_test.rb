require "test_helper"

class Admin::ChipInputComponentTest < ViewComponent::TestCase
  def render_chips(**overrides)
    render_inline Admin::ChipInputComponent.new(
      name: "post[tag_names][]", id: "post-tag_names", label: "Tags", search_url: "/cs-studio/tags/suggest",
      chips: [ { value: "rails", label: "rails" }, { value: "ruby", label: "ruby" } ], **overrides
    )
  end

  test "each chip is an li with a named remove button and its own hidden input" do
    render_chips

    assert_selector "li[data-chip-value='rails']", text: "rails"
    assert_selector "li[data-chip-value='rails'] button[aria-label='Remove rails']"
    assert_selector "li[data-chip-value='rails'] input[type=hidden][name='post[tag_names][]'][value='rails']", visible: :all
    assert_selector "li[data-chip-value='ruby'] button[aria-label='Remove ruby']"
  end

  test "an empty sentinel is submitted ahead of the chips so an emptied list still saves" do
    render_chips(chips: [])

    assert_selector "input[type=hidden][name='post[tag_names][]'][value='']", count: 1, visible: :all
    assert_no_selector "li[data-chip-value]"
  end

  test "the text input is a combobox owning an empty, hidden listbox" do
    render_chips

    assert_selector "input[role=combobox][id='post-tag_names'][aria-expanded='false'][aria-controls='post-tag_names-listbox'][aria-autocomplete='list']"
    assert_selector "ul[role=listbox]#post-tag_names-listbox[hidden]", visible: :all
    assert_no_selector "#post-tag_names-listbox li", visible: :all
    assert_no_selector "input[role=combobox][name]"
  end

  test "the label is tied to the input and additions are announced through a polite live region" do
    render_chips

    assert_selector "label[for='post-tag_names']", text: "Tags"
    assert_selector "[role=status][aria-live=polite]", visible: :all
  end

  test "a chip's dot and hint render when given" do
    render_chips(chips: [ { value: "7", label: "Hub", hint: "Draft", dot: "bg-cat-2" } ])

    assert_selector "li[data-chip-value='7'] .bg-cat-2"
    assert_selector "li[data-chip-value='7']", text: "· Draft"
  end

  test "an invalid chip is tinted danger and flagged" do
    render_chips(chips: [ { value: "bad", label: "bad", invalid: true } ])

    assert_selector "li[data-chip-value='bad'].bg-danger-tint[data-invalid]"
  end

  test "the controller's configuration is on the root" do
    render_chips(create: true, noun: "tag")

    assert_selector "[data-controller='admin--chip-input'][data-admin--chip-input-search-url-value='/cs-studio/tags/suggest'][data-admin--chip-input-create-value='true']"
  end

  test "errors and the hidden note render" do
    render_chips(errors: [ "is too long" ], hidden_note: "+2 related posts you can’t open")

    assert_selector "#post-tag_names-errors p", text: "is too long"
    assert_text "+2 related posts you can’t open"
  end
end
