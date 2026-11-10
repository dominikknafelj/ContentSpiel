module Admin
  module Ui
    # The three-way theme control: Light,
    # Dark, or Auto (follow the OS). Which button is "on" is painted by CSS
    # from `<html data-theme-choice>` -- set before first paint by
    # shared/_theme_head -- so the right one is marked before Stimulus
    # connects; `theme_controller.js` keeps `aria-checked` and the roving
    # `tabindex` in step and moves the choice with the arrow keys.
    #
    # The choices are buttons with `role="radio"`, not native radio inputs: a
    # native group's checked input is form state, which the browser restores
    # on a back or forward visit and Turbo's snapshot keeps, so it could
    # disagree with the stored choice that `<html data-theme-choice>` paints
    # from; and before the script connects nothing would be checked, so a
    # native group's Tab stop would be its first or last input, not the
    # choice. The buttons keep one source, the html element, and the script
    # gives them the APG radio group's keys.
    class ThemeSwitchComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A radiogroup named Theme of three radio buttons, Light, Dark and Auto: one Tab stop, the checked one (a roving tabindex), and Left or Up and Right or Down choose the previous or next and move the focus to it, wrapping at the ends; the theme script keeps aria-checked in step.",
        motion: :reduced,
        content_edges: %i[short],
        widths: :fluid,
        interface: [],
        limits: [
          "Which choice is on is painted from the html element's data-theme-choice, never from the component.",
          "Until the theme script connects every choice is a Tab stop: the server cannot know the stored choice, which lives in the browser."
        ],
        states: %i[rest hover focus],
        script_states: {
          chosen: [ "test/system/theme_toggle_test.rb", "light, dark and auto each apply, survive a reload, and mark the chosen button" ]
        },
        keys: %w[label light dark auto],
        slots: [],
        controller: "theme",
        keyboard: [ "test/system/admin/keyboard_navigation_test.rb", "the theme switch is one Tab stop, the checked choice, and the arrows choose the previous or next, move the focus with it and wrap" ]
      )

      CHOICES = %w[light dark auto].freeze
    end
  end
end
