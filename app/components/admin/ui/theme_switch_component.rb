module Admin
  module Ui
    # The three-way theme control: Light,
    # Dark, or Auto (follow the OS). Which button is "on" is painted by CSS
    # from `<html data-theme-choice>` -- set before first paint by
    # shared/_theme_head -- so the right one is marked before Stimulus
    # connects; `theme_controller.js` only keeps `aria-checked` in step.
    class ThemeSwitchComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A radiogroup named Theme of three radio buttons, Light, Dark and Auto, whose aria-checked the theme script keeps in step.",
        motion: :reduced,
        content_edges: %i[short],
        widths: :fluid,
        interface: [],
        limits: [
          "Which choice is on is painted from the html element's data-theme-choice, never from the component.",
          "Its words (Theme, Light, Dark, Auto) are English in the code and template, not keys."
        ],
        states: %i[rest hover focus],
        script_states: {
          chosen: [ "test/system/theme_toggle_test.rb", "light, dark and auto each apply, survive a reload, and mark the chosen button" ]
        },
        keys: [],
        slots: [],
        controller: "theme",
        keyboard: [ "test/system/admin/keyboard_navigation_test.rb", "the theme switch's choices are one Tab stop each, and Enter or Space on one chooses it and marks it checked" ]
      )

      CHOICES = { "light" => "Light", "dark" => "Dark", "auto" => "Auto" }.freeze
    end
  end
end
