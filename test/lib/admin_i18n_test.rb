require "test_helper"
require "ripper"

# No English in the converted CS Studio files (docs/reference/i18n.md). A string
# a user reads comes from a locale file through `t(".key")` (or, for a script,
# `messages(element).t(key)`), so a translator finds it in one place and the
# German UI is a matter of adding a file. `CONVERTED` lists the files that
# have been converted; the guard holds each of them to the rule, and the list
# grows with every screen the German UI sub-project converts. A listed path that
# does not exist fails, so a rename can't drop a file out of the guard.
#
# THE RULES. "Copy" is anything a person reads: a text node, an attribute that
# carries words, a string a component puts into its markup.
#
# - ERB markup: no text node with a letter in it once the ERB tags are taken
#   out (entities and glyphs such as "·", "→", "×", "⠿" are not letters), and
#   no `aria-label`, `title`, `placeholder` or `alt` attribute -- nor the
#   `value` of a button -- with a literal letter in it. `aria-label="<%= label
#   %> suggestions"` has a literal word in it, so it fails.
# - Ruby, in a component, a helper-ish file or the Ruby inside an ERB tag: no
#   string literal that is copy. A literal is copy when its text (interpolations
#   don't count) holds a capitalised word ("Cancel", "Couldn't save"), a word in
#   capitals of three letters or more ("SAVING"), or two words ending in a
#   sentence mark ("try again."). That one rule is also what keeps CSS out
#   without a list of exceptions: a Tailwind class, a CSS constant, a `data`
#   key, an id, a symbol and a `strftime` pattern are all lower-case tokens
#   ("flex items-center gap-1.5", "admin--save-bar-target", "%-d %b"), and a
#   class name written as `Admin::Foo` has a `::`. What it deliberately lets
#   through: a lower-case sentence ("just now"), which a test or a review
#   catches. Excluded: comments (the lexer never reports them), a line that
#   starts `raise` (a message for a developer), and a line that ends in
#   `# i18n-ok: <reason>`.
# - JavaScript: no string literal that reads as a sentence, a capitalised word
#   (with its apostrophe) and then a lower-case one ("Couldn't save the new order"), and none that ends in an ellipsis after a
#   word. Comments and regular expressions are skipped by a small scanner.
#
# The rules are pinned against small samples at the foot of this file, as the
# other guards here are.
class AdminI18nTest < ActiveSupport::TestCase
  CONVERTED = %w[
    app/views/layouts/admin.html.erb
    app/components/admin/button_component.rb
    app/components/admin/button_component.html.erb
    app/components/admin/dialog_component.rb
    app/components/admin/dialog_component.html.erb
    app/components/admin/confirm_dialog_component.rb
    app/components/admin/confirm_dialog_component.html.erb
    app/components/admin/toast_component.rb
    app/components/admin/toast_component.html.erb
    app/components/admin/toast_region_component.rb
    app/components/admin/toast_region_component.html.erb
    app/components/admin/save_bar_component.rb
    app/components/admin/save_bar_component.html.erb
    app/components/admin/save_status_component.rb
    app/components/admin/save_status_component.html.erb
    app/components/admin/status_chip_component.rb
    app/components/admin/status_chip_component.html.erb
    app/components/admin/translation_chip_component.rb
    app/components/admin/language_tabs_component.rb
    app/components/admin/language_tabs_component.html.erb
    app/components/admin/pagination_component.rb
    app/components/admin/pagination_component.html.erb
    app/components/admin/time_ago_component.rb
    app/components/admin/empty_state_component.rb
    app/components/admin/empty_state_component.html.erb
    app/components/admin/error_summary_component.rb
    app/components/admin/error_summary_component.html.erb
    app/components/admin/chip_input_component.rb
    app/components/admin/chip_input_component.html.erb
    app/components/admin/menu_component.rb
    app/components/admin/menu_component.html.erb
    app/helpers/admin/messages_helper.rb
    app/javascript/i18n/messages.js
    app/javascript/controllers/admin/save_bar_controller.js
    app/javascript/controllers/admin/pending_lock_controller.js
    app/javascript/controllers/admin/chip_input_controller.js
    app/javascript/controllers/admin/autosave_controller.js
    app/javascript/autosave/order_request.js
    app/javascript/autosave/queue.js
  ].freeze

  PLACEHOLDER = "".freeze
  COPY_ATTRIBUTES = %w[aria-label title placeholder alt].freeze

  # A tag the HTML parser should not look inside for words.
  NOT_MARKUP = %w[script style].freeze

  # --- ERB ------------------------------------------------------------------

  # Splits a template into its Ruby (each `<% %>` tag's code, comments left
  # out) and its markup (the tags replaced by a placeholder, so `<div class="a
  # <%= b %>">` stays one tag). Returns [markup, [ruby, ...]].
  def split_erb(source)
    source = source.gsub(/<%#.*?%>/m, "")
    code = source.scan(/<%[-=]?(.*?)-?%>/m).flatten
    [ source.gsub(/<%.*?%>/m, PLACEHOLDER).gsub(/<!--.*?-->/m, ""), code ]
  end

  def markup_offences(markup)
    fragment = Nokogiri::HTML5.fragment(markup)
    found = fragment.xpath(".//text()").filter_map do |node|
      next if NOT_MARKUP.include?(node.parent.name)

      text = node.text.delete(PLACEHOLDER)
      "text: #{text.strip.inspect}" if text.match?(/\p{L}/)
    end
    fragment.xpath(".//*").each do |element|
      COPY_ATTRIBUTES.each do |name|
        value = element[name]
        found << "#{name}=#{value.inspect}" if value && value.delete(PLACEHOLDER).match?(/\p{L}/)
      end
      next unless element.name == "button" || (element.name == "input" && %w[button submit].include?(element["type"]))

      value = element["value"]
      found << "value=#{value.inspect}" if value && value.delete(PLACEHOLDER).match?(/\p{L}/)
    end
    found
  end

  # --- Ruby -----------------------------------------------------------------

  # Whether the text of one string literal is copy (see the rules at the top).
  def copy?(text)
    return false if text.include?("::")

    text.match?(/\b[A-Z][a-z]+\b/) || text.match?(/\b[A-Z]{3,}\b/) || text.match?(/\p{L}\s+\p{L}.*[.!?…]\z/)
  end

  def ruby_offences(source)
    lines = source.lines
    Ripper.lex(source).filter_map do |(line, _column), type, text|
      next unless type == :on_tstring_content && copy?(text)

      code = lines[line - 1].to_s
      next if code.strip.start_with?("raise ") || code.match?(/#\s*i18n-ok:\s*\S/)

      "#{line}: #{text.strip.inspect}"
    end
  end

  # --- JavaScript -----------------------------------------------------------

  # The string literals of a script, each with its line, skipping comments and
  # regular expression literals. A template literal is one literal (its
  # `${...}` parts are inside it); good enough for a rule about words.
  def js_literals(source)
    literals = []
    i = 0
    line = 1
    last = nil # the last significant character, to tell a `/` that divides from one that opens a regexp
    while i < source.length
      char = source[i]
      pair = source[i, 2]
      if pair == "//"
        i += 1 until i >= source.length || source[i] == "\n"
      elsif pair == "/*"
        close = source.index("*/", i + 2) || source.length
        line += source[i...close].count("\n")
        i = close + 2
      elsif %w[" ' `].include?(char)
        start = i
        i += 1
        i += (source[i] == "\\" ? 2 : 1) until i >= source.length || source[i] == char
        text = source[(start + 1)...i]
        literals << [ line, text ]
        line += text.count("\n")
        i += 1
        last = char
      elsif char == "/" && (last.nil? || "(,=:[!&|?{};".include?(last))
        i += 1
        in_class = false
        while i < source.length && (in_class || source[i] != "/")
          in_class = true if source[i] == "["
          in_class = false if source[i] == "]"
          i += 1 if source[i] == "\\"
          i += 1
        end
        i += 1
        last = "/"
      else
        line += 1 if char == "\n"
        last = char unless char.match?(/\s/)
        i += 1
      end
    end
    literals
  end

  def js_sentence?(text)
    text.match?(/[A-Z][a-z]+['’]?[a-z]* [a-z]/) || text.match?(/\p{L}\s*…\z/)
  end

  def js_offences(source)
    js_literals(source).filter_map { |line, text| "#{line}: #{text.strip.inspect}" if js_sentence?(text) }
  end

  # --- The checks -----------------------------------------------------------

  def offences_in(path)
    source = File.read(Rails.root.join(path))
    case File.extname(path)
    when ".erb"
      markup, code = split_erb(source)
      markup_offences(markup) + code.flat_map { |ruby| ruby_offences(ruby) }
    when ".rb" then ruby_offences(source)
    when ".js" then js_offences(source)
    else flunk "#{path}: no rule for this kind of file"
    end
  end

  test "every converted file exists" do
    assert_operator CONVERTED.size, :>, 30, "the list shrank: this guard is looking at too little"
    assert_equal [], CONVERTED.reject { |path| Rails.root.join(path).file? }
    assert_equal CONVERTED.uniq, CONVERTED
  end

  test "the converted files hold no English of their own" do
    found = CONVERTED.flat_map { |path| offences_in(path).map { |offence| "#{path}: #{offence}" } }

    assert_empty found, "Move these into config/locales/admin/ and read them with t(\".key\") (docs/reference/i18n.md):\n#{found.join("\n")}"
  end

  test "every shared component an admin screen uses without owning its copy is listed or named here" do
    # The ones that take their words from the caller are in CONVERTED and
    # pass the rule; this pins that none of the sixteen was forgotten.
    sixteen = %w[button dialog confirm_dialog toast toast_region save_bar status_chip translation_chip language_tabs
      pagination time_ago empty_state error_summary chip_input menu save_status]
    sixteen.each do |name|
      assert CONVERTED.any? { |path| path == "app/components/admin/#{name}_component.rb" }, "#{name}_component.rb is not in CONVERTED"
    end
  end

  # --- The rules, pinned ------------------------------------------------------

  test "markup: a literal word in a text node or a copy attribute is an offence, a lookup is not" do
    clean = ->(erb) { markup_offences(split_erb(erb).first) }

    assert_empty clean.(%(<p class="a"><%= t(".x") %></p>))
    assert_empty clean.(%(<span aria-hidden="true">×</span> · → ⠿ &nbsp; &amp;))
    assert_empty clean.(%(<button aria-label="<%= t(".close") %>" title="<%= x %>">×</button>))
    assert_empty clean.(%(<p data-action="click->a#b"><%# a comment with Words %></p>))
    assert_empty clean.(%(<script>var s = "Some words"</script>))
    assert_equal [ %(text: "Cancel") ], clean.(%(<button>Cancel</button>))
    assert_equal [ %(text: "OF") ], clean.(%(<p><%= a %> OF <%= b %></p>))
    assert_equal [ %(aria-label="Close") ], clean.(%(<button aria-label="Close"></button>))
    assert_equal [ %(aria-label="<%= label %> suggestions") ].map { |s| s.gsub("<%= label %>", PLACEHOLDER) }, clean.(%(<ul aria-label="<%= label %> suggestions"></ul>))
    assert_equal [ %(placeholder="Search") ], clean.(%(<input placeholder="Search">))
    assert_equal [ %(value="Save") ], clean.(%(<input type="submit" value="Save">))
    assert_equal [ %(alt="Logo") ], clean.(%(<img alt="Logo">))
    assert_empty clean.(%(<input type="hidden" name="a" value="draft">))
  end

  test "Ruby: copy is a capitalised word, a word in capitals or a sentence, never a CSS token or a key" do
    [ "Cancel", "Couldn't save", "Save or cancel your changes first.", "SAVING…", "NOT SAVED · ", "Remove #", "try again." ].each do |text|
      assert copy?(text), "#{text.inspect} should count as copy"
    end
    [ "flex items-center gap-1.5 rounded-cs", "admin--save-bar-target", "bg-meta", "%-d %b %Y, %H:%M", "min-h-[1lh]", "admin.datetime",
      "Admin::DialogComponent", "", " ", "·", "dialog", "just", "language-switcher-outdated-" ].each do |text|
      assert_not copy?(text), "#{text.inspect} should not count as copy"
    end
  end

  test "Ruby: the lexer skips comments, `raise` lines and an i18n-ok line" do
    assert_equal [ %(1: "Cancel") ], ruby_offences(%(label = "Cancel"\n))
    assert_empty ruby_offences(%(# label = "Cancel"\n))
    assert_empty ruby_offences(%(raise ArgumentError, "Unknown thing"\n))
    assert_empty ruby_offences(%(x = "Cancel" # i18n-ok: a product name\n))
    assert_equal [ %(2: "Retry") ], ruby_offences(%(a = "ok"\nb = { class: "x", title: "Retry" }\n))
    assert_empty ruby_offences(%(t(".cancel", label: label)\ntag.span class: "a b", data: { "admin--x-target": "y" }\n))
  end

  test "JavaScript: a sentence in a literal is an offence, a comment, a regexp or a key is not" do
    assert_equal [ %(1: "Couldn't save the new order") ], js_offences(%(const a = "Couldn't save the new order"\n))
    assert_equal [ %(1: "Search…") ], js_offences(%(x = 'Search…'\n))
    assert_equal [ %(1: "Added a tag") ], js_offences("x = `Added a tag`\n")
    assert_empty js_offences(%(// "Couldn't save the new order"\nconst a = "components.save_bar.blocked"\n))
    assert_empty js_offences(%(/* "Save or cancel" */ x.replace(/'Save or "cancel/g, "")\n))
    assert_empty js_offences(%(const total = a / b; const k = "admin--save-bar"\n))
    assert_empty js_offences(%(x.querySelector("[data-leave-count]").dataset.foo = "NOT"\n))
  end
end
