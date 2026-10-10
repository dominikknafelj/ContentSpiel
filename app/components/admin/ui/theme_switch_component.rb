module Admin
  module Ui
    # The three-way theme control (design pass spec §4, handoff §1): Light,
    # Dark, or Auto (follow the OS). Which button is "on" is painted by CSS
    # from `<html data-theme-choice>` -- set before first paint by
    # shared/_theme_head -- so the right one is marked before Stimulus
    # connects; `theme_controller.js` only keeps `aria-checked` in step.
    class ThemeSwitchComponent < AdminComponent
      CHOICES = { "light" => "Light", "dark" => "Dark", "auto" => "Auto" }.freeze
    end
  end
end
