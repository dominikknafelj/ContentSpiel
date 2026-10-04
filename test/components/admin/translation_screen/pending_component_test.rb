require "test_helper"

# The "waiting for a suggestion" box (design pass round 2, §A-suggestions):
# rendered once into a `<template>` in the layout and cloned by
# `admin--translate` before each request. Two states in one element -- the
# running one (spinner, elapsed seconds, two skeleton bars, Cancel) and the
# 25-second one -- the controller flips with `hidden`.
class Admin::TranslationScreen::PendingComponentTest < ViewComponent::TestCase
  test "the running state: spinner, elapsed seconds, two skeleton bars and Cancel" do
    render_inline Admin::TranslationScreen::PendingComponent.new

    assert_selector "[data-translation-pending].bg-accent-tint"
    assert_selector "[data-pending-running] [data-translate-spinner]"
    assert_selector "[data-pending-running] [data-pending-elapsed]", text: "0s"
    assert_selector "[data-pending-running] [data-pending-skeleton]", count: 2
    assert_selector "[data-pending-running] button[type='button'][data-action='admin--translate#cancelPending']", text: "Cancel"
  end

  test "the 25 second state is there but hidden, with Try again" do
    render_inline Admin::TranslationScreen::PendingComponent.new

    assert_selector "[data-pending-timeout][hidden]", visible: :hidden
    assert_equal "No suggestion after 25 seconds.", page.find("[data-pending-timeout] p", visible: :all).text(:all)
    assert_selector "[data-pending-timeout] button[type='button'][data-action='admin--translate#retry']", text: "Try again", visible: :hidden
    assert_equal 25, Admin::TranslationScreen::PendingComponent::TIMEOUT_SECONDS
  end

  test "the box says it is busy to screen readers" do
    render_inline Admin::TranslationScreen::PendingComponent.new

    assert_selector "[data-translation-pending][role='status']"
  end
end
