module Admin
  module Ui
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
    class TranslationPendingComponent < Admin::AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Cancel and Try again are real buttons that are one Tab stop each (Try again only once it shows), pressed with Enter or Space; the box is no live region of its own, the field's polite box announces its arrival once, the counter is hidden from screen readers, and the timeout sentence is written into its element when the time comes.",
        motion: :reduced,
        content_edges: %i[short],
        widths: :fluid,
        interface: %i[],
        limits: [
          "It is never drawn into a page by the server: the layout holds one copy in #translation-pending-template and admin--translation--translate clones it into a field's box before each request.",
          "Its two states (running, timed out) are both in the markup and flipped with hidden by the script, which ticks the seconds and writes the timeout sentence; the words it writes come from the box's own data-messages and its data-pending-timeout-text.",
          "Its buttons are type=button, since the box sits inside an autosave form; it carries no controller of its own."
        ],
        states: %i[running],
        keys: %w[running elapsed cancel timeout try_again],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/translations_test.rb", "a pending box's Cancel is one Tab stop that Enter presses" ]
      )

      TIMEOUT_SECONDS = 25

      # What the script writes into the box, by key below `admin`.
      MESSAGES = %w[components.ui.translation_pending.elapsed].freeze

      def timeout_text = t(".timeout", seconds: TIMEOUT_SECONDS)

      def messages = messages_data(*MESSAGES)
    end
  end
end
