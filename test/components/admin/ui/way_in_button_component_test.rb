require "test_helper"

class Admin::Ui::WayInButtonComponentTest < ViewComponent::TestCase
  test "a submit button in a POST form of its own, sent without Turbo, with the button's look" do
    render_inline Admin::Ui::WayInButtonComponent.new(label: "Sign in with Okta", url: "/start")

    form = page.find("form[action='/start'][method=post][data-turbo=false]")
    button = form.find("button[type=submit]", text: "Sign in with Okta")
    assert_equal "#{Admin::Ui::ButtonComponent.classes(:secondary)} w-full", button[:class]
  end

  # The test environment turns forgery protection off, which drops every
  # form's token: it is turned on for the one render that shows it.
  test "its form carries the form's token" do
    before = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    render_inline Admin::Ui::WayInButtonComponent.new(label: "Sign in with Okta", url: "/start")
    assert_selector "form input[type=hidden][name=authenticity_token]", visible: :all
  ensure
    ActionController::Base.allow_forgery_protection = before
  end

  test "the primary is full width, the tertiary small at its own width" do
    render_inline Admin::Ui::WayInButtonComponent.new(label: "Sign in with Okta", url: "/start", variant: :primary)
    assert_equal "#{Admin::Ui::ButtonComponent.classes(:primary)} w-full", page.find("button")[:class]

    render_inline Admin::Ui::WayInButtonComponent.new(label: "Sign in with Okta instead", url: "/start", variant: :tertiary)
    assert_equal Admin::Ui::ButtonComponent.classes(:tertiary, size: :small), page.find("button")[:class]
  end

  test "an unknown variant is a programming error" do
    assert_raises(ArgumentError) { Admin::Ui::WayInButtonComponent.new(label: "x", url: "/start", variant: :danger) }
  end
end
