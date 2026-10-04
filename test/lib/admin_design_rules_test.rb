require "test_helper"

# Design pass spec §3: tokens only, red only for destruction and failure,
# and none of the components the shared parts replaced. These rules are easy to
# break one innocent edit at a time, so they are pinned here.
class AdminDesignRulesTest < ActiveSupport::TestCase
  ADMIN_SOURCES = Dir[Rails.root.join("app/{views/admin,views/layouts,views/setup,components/admin,javascript/controllers}/**/*.{erb,rb,js}")]

  # A raw colour literal, in any of the spellings CSS has for one:
  # - hex with 3, 4, 6 or 8 digits. The lookbehind is what keeps the things
  #   that merely look like one out: a Stimulus action (`admin--menu#add`), a
  #   Ruby interpolation (`"##{id}"`), an HTML character reference (`&#8203;`)
  #   and a URL fragment (`/path#fade`) all have a word character, `#`, `&` or
  #   `/` in front of the `#`. An id selector that happens to spell hex
  #   digits (`"#feed"`) would still be flagged -- rename the id.
  # - `rgb(` / `rgba(` / `hsl(` / `hsla(`.
  RAW_COLOUR = /(?<![\w#&\/-])#(?:\h{8}|\h{6}|\h{3,4})(?![\w-])|\b(?:rgb|hsl)a?\(/

  # Any `dark:` variant -- `dark:bg-…`, an arbitrary `dark:[…]`, a stacked
  # `dark:hover:bg-…` or `hover:dark:bg-…` -- except `dark:scheme-dark`, the
  # one place the theme is handed to the browser's own controls. Tokens
  # already switch with the theme, so a `dark:` class is always a second,
  # diverging source of colour. A variant is followed by a utility; prose
  # about the rule ("no `dark:` variants") is not.
  DARK_VARIANT = /(?<![\w-])dark:(?!scheme-dark(?![\w-]))[a-z\[!-]/

  # The one file allowed a `dark:` variant: the public site's footer toggle
  # swaps its two labels with `dark:hidden` / `dark:inline`. That is which
  # *text* shows, not a colour, and it belongs to the public theme (it only
  # sits under `views/layouts`), so there is no token to replace it with.
  DARK_VARIANT_EXEMPT = %w[app/views/layouts/public/_theme_toggle.html.erb].freeze

  def design_offences(pattern, except: [])
    (ADMIN_SOURCES - except.map { |path| Rails.root.join(path).to_s }).flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        "#{Pathname(path).relative_path_from(Rails.root)}:#{index + 1}: #{line[pattern]}" if line.match?(pattern)
      end
    end
  end

  test "no raw colour literals in CS Studio" do
    assert_empty design_offences(RAW_COLOUR)
  end

  test "no dark: variants in CS Studio except dark:scheme-dark" do
    assert_empty design_offences(DARK_VARIANT, except: DARK_VARIANT_EXEMPT)
    DARK_VARIANT_EXEMPT.each do |path|
      assert_equal %w[dark:hidden dark:inline], Rails.root.join(path).read.scan(/dark:[\w-]+/), "#{path} is exempt for its label swap only"
    end
  end

  # The guard is only worth having if its patterns catch what they claim to
  # and nothing else, so both are pinned against examples.
  test "the guard patterns match colours and dark: variants, and nothing that only looks like one" do
    [ "color: #fff", "fill='#1a2b3c'", "stroke: #1a2b3c80;", "bg-[#abcd]", "background: rgb(0 0 0 / 50%)", "rgba(0,0,0,.5)",
      "hsl(210 50% 40%)", "hsla(210, 50%, 40%, .5)" ].each do |sample|
      assert_match RAW_COLOUR, sample
    end
    [ 'find("#toasts")', "#content", 'action: "admin--menu#add"', "admin--tree#face", '"##{dom_id}"', "&#8203;", "&#x200b;",
      "/cs-studio/pages#add", "#fade-in", "issue #12345", "#abcde" ].each do |sample|
      assert_no_match RAW_COLOUR, sample
    end

    [ "dark:bg-ink", "dark:text-paper", "dark:hover:bg-sunken", "hover:dark:bg-sunken", "dark:[color:red]", "dark:shadow-menu",
      "dark:!bg-ink", "dark:-mt-1", "scheme-light dark:scheme-dark dark:border-line" ].each do |sample|
      assert_match DARK_VARIANT, sample
    end
    [ "scheme-light dark:scheme-dark", "no `dark:` colour variant", '{ dark: "x" }', "data-dark:bg" ].each do |sample|
      assert_no_match DARK_VARIANT, sample
    end
  end

  test "translation chips and language tabs never use the danger colour" do
    %w[app/components/admin/translation_chip_component.rb app/components/admin/language_tabs_component.html.erb].each do |path|
      assert_no_match(/danger/, Rails.root.join(path).read, path)
    end
  end

  test "the replaced components are gone" do
    %w[
      status_badge_component.rb language_switcher_component.rb flash_component.rb translation_screen/state_badge_component.rb
      record_header_component.rb tag_input_component.rb translation_screen/list_component.rb
      translation_screen/outdated_note_component.rb dashboard_screen/column_component.rb
    ].each do |file|
      assert_not Rails.root.join("app/components/admin", file).exist?, file
    end
    assert_not Rails.root.join("app/views/shared/_theme_toggle.html.erb").exist?
    # The translation states live in `translation_states` (`Translations::StateIndex`) now.
    assert_not Rails.root.join("app/models/translations/cached_status.rb").exist?
  end

  test "the outlined danger button variant is gone" do
    offenders = Dir[Rails.root.join("app/**/*")].select { |f| File.file?(f) && File.read(f).include?("danger_outline") }
    assert_empty offenders.map { |f| Pathname(f).relative_path_from(Rails.root).to_s }
  end
end
