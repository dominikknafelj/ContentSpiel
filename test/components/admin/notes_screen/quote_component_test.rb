require "test_helper"

class Admin::NotesScreen::QuoteComponentTest < ViewComponent::TestCase
  test "the quote is a figure whose caption is its first child, and the passage is escaped text" do
    render_inline(Admin::NotesScreen::QuoteComponent.new(quote: "€49 a <b>month</b>\nand more"))

    assert_selector "figure[data-note-quote] > figcaption:first-child", text: "Quoted"
    assert_selector "figure[data-note-quote] > blockquote:last-child", text: "€49 a <b>month</b>"
    assert_no_selector "figure div figcaption"
    assert_no_selector "b"
  end

  test "no quote, no figure" do
    render_inline(Admin::NotesScreen::QuoteComponent.new(quote: " "))

    assert_no_selector "figure"
  end
end
