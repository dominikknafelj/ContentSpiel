require "test_helper"

# No inline event handlers: they hide behaviour from the Stimulus controllers
# that own it, and a script Content-Security-Policy (a roadmap row; the app
# sends none today) would refuse every one of them. Behaviour is wired through
# `data-action`; dialogs open through `data: dialog_trigger(id)`.
#
# This test is the whole enforcement, so it looks for ANY handler attribute,
# not a list of the usual ones (`ondrop`, `ondblclick`, `onpaste`,
# `onpointerdown` and `ontoggle` were all outside the old list), in the two
# places one can be written:
#
# 1. as an HTML attribute, in markup -- a template, a Ruby string or a
#    JavaScript template string: `on<anything>=` inside a tag;
# 2. as a key handed to a tag helper -- `onclick: "…"`, `"ondrop" => "…"`.
#    Ruby has ordinary keywords that begin with "on" (`only:`, `once:`), so
#    here the name must be `on` + a real DOM event.
class InlineHandlersTest < ActiveSupport::TestCase
  # `on…=` in attribute position: after the tag's name and whitespace, before
  # the tag closes. (`data-action="click->…"`, `aria-controls=…`, a variable
  # called `only` and SortableJS's `onStart:` are none of that.)
  HTML_ATTRIBUTE = /<[a-zA-Z][\w:-]*\b[^<>]*?\s(on[a-z]+)\s*=/

  # Every event a handler attribute exists for, by family.
  EVENTS = %w[
    click dblclick auxclick contextmenu change input beforeinput submit reset invalid formdata select\w* search
    key\w+ mouse\w+ pointer\w+ touch\w+ drag\w* drop wheel scroll\w* focus\w* blur load\w* unload beforeunload
    error abort resize toggle beforetoggle close cancel copy cut paste animation\w+ transition\w+ play\w* pause ended
    canplay\w* timeupdate volumechange seek\w+ stalled suspend waiting emptied durationchange ratechange progress cuechange
    message\w* popstate hashchange storage online offline pageshow pagehide languagechange visibilitychange
    securitypolicyviolation slotchange beforeprint afterprint beforematch
  ].freeze
  HELPER_KEY = /(?<![\w.])["']?(on(?:#{EVENTS.join("|")}))["']?\s*(?:=>|:(?!:))/

  # ERB tags out of the way first: their `>` (`%>`, `->`) would end a tag early
  # and hide the attributes after them, and their Ruby is checked as Ruby.
  def markup_of(path, source)
    path.end_with?(".erb") ? source.gsub(/<%.*?%>/m, "ERB") : source
  end

  def offences(pattern, paths)
    paths.flat_map do |path|
      source = File.read(path)
      source = markup_of(path, source) if pattern == HTML_ATTRIBUTE
      source.scan(pattern).flatten.uniq.map { |name| "#{Pathname(path).relative_path_from(Rails.root)}: #{name}" }
    end
  end

  test "no markup carries an inline event handler attribute" do
    paths = Dir[Rails.root.join("app/{views,components,helpers}/**/*.{erb,rb}"), Rails.root.join("app/javascript/**/*.js")]
    assert_operator paths.size, :>, 300, "the sources moved: this guard is looking at too little"
    assert_empty offences(HTML_ATTRIBUTE, paths)
  end

  test "no view, component or helper hands a tag helper an inline event handler" do
    paths = Dir[Rails.root.join("app/{views,components,helpers}/**/*.{erb,rb}")]
    assert_empty offences(HELPER_KEY, paths)
  end

  # The guard is only worth having if its patterns catch what they claim to
  # and nothing else, so both are pinned against examples.
  test "the patterns match handlers, and nothing that only looks like one" do
    [ %(<button onclick="go()">), %(<div class="x" ondrop='take(event)'>), %(<details ontoggle=refresh()>), %(<img src="a.png"\n  onerror = "x">),
      %(<input onpaste="x">), %(<li ondragstart="x" draggable>), %(<a href="#" onpointerdown="x">), %(<button class="ERB" ondblclick="x">),
      %(<x-thing onwhatever="x">) ].each do |sample|
      assert_match HTML_ATTRIBUTE, sample
    end
    [ %(<button data-action="click->admin--dialog#open">), %(<div data-controller="x" aria-controls="only">), %(<p>once = twice</p>),
      %(only = "x"), %(onStart: (event) => this.start(event)), %(new Sortable(list, { onEnd: done })), %(<form data-turbo-confirm="on = off">x</form>),
      %(for (let i = 0; i < count; i++) { once = true }), %(<option value="on">on = default</option>) ].each do |sample|
      assert_no_match HTML_ATTRIBUTE, sample
    end

    [ %(tag.button("x", onclick: "go()")), %(button_to "x", path, "ondrop" => "take()"), %(html: { onchange: "this.form.submit()" }),
      %(link_to "x", "#", :onmouseover => "x"), %(onkeydown: "x"), %(ondblclick: "x"), %(onpaste: "x"), %(ontoggle: "x"), %(onpointerdown: "x"),
      %(ondragover: "x"), %(onfocusin: "x"), %(onsubmit: "return false") ].each do |sample|
      assert_match HELPER_KEY, sample
    end
    [ %(only: %i[show edit]), %(once: true), %(on: :create), %(ongoing: true), %(online: true), %(data: { action: "click->x#y" }),
      %(config.onerror), %(Sortable::onEnd), %(one: 1), %(condition: x) ].each do |sample|
      assert_no_match HELPER_KEY, sample
    end
  end
end
