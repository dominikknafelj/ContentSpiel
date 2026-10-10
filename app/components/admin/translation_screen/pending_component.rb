module Admin
  module TranslationScreen
    # The box that stands in a field's suggestion slot while a request is out
    # (design pass round 2, handoff §10 "Pending suggestion"): an accent-tint
    # box with a spinner, the seconds waited, two skeleton bars and Cancel.
    # After `TIMEOUT_SECONDS` it says "No suggestion after 25 seconds." with a
    # **Try again** button instead.
    #
    # It is never rendered into a page by the server: the layout holds one copy
    # inside a `<template>` and `admin--translation--translate` clones it into the field's
    # box (`[data-translation-box]`) before each request, so the box exists the
    # instant the editor presses the button. Both states are in the markup;
    # the controller flips them with `hidden` and ticks `[data-pending-elapsed]`
    # from its own timer. The 25 s is the provider's own timeout
    # (`AI::Providers::Anthropic::TIMEOUT`, pinned by its test): the server
    # gives up at the same moment, so a later answer for a box that timed out
    # is stale and the controller ignores it unless Try again was pressed.
    #
    # Its buttons are `type="button"`: the box sits inside an autosave `<form>`.
    # Cancel / Try again are `admin--translation--translate#cancelPending` / `#retry`, run by
    # the box's own controller instance (`admin/shared/_translation_box`).
    class PendingComponent < Admin::AdminComponent
      TIMEOUT_SECONDS = 25
      TIMEOUT_TEXT = "No suggestion after #{TIMEOUT_SECONDS} seconds.".freeze
    end
  end
end
