require "test_helper"

# theme.yml: the lists a theme declares, read as data from outside. Nothing
# a file contains may raise: each wrong value is one problem naming the list,
# the entry's place and the key.
class Theme::DeclarationsTest < ActiveSupport::TestCase
  def read(yaml, **options) = Theme::Declarations.read(yaml, file: "theme.yml", **options)

  def problems(yaml) = read(yaml).last

  def one_problem(yaml, *parts)
    found = problems(yaml)

    assert_equal 1, found.size, found.inspect
    assert found.first.start_with?("theme.yml"), found.first
    parts.each { |part| assert_includes found.first, part }
    found.first
  end

  test "a list a theme does not declare is the default's, and a declared one replaces it, an empty one included" do
    with_theme_copy do |dir|
      folder = ThemeFolder.new(dir)

      assert_equal Theme::Declarations.default, Theme::Declarations.of(folder)

      dir.join("theme.yml").write("section_styles:\n  - name: services\n    label: Services\npage_templates: []\n")
      lists = Theme::Declarations.of(ThemeFolder.new(dir))

      assert_equal %w[services], lists["section_styles"].map(&:name)
      assert_empty lists["page_templates"]
      assert_equal Theme::Declarations.default["icons"], lists["icons"]
    end
  end

  test "an entry naming the default's entry with no file of its own is the default's, and its label and fields are the theme's" do
    default = Theme::Choice.new(list: "icons", name: "arrow", labels: { "en" => "Arrow" }, fields: [], file: "icons/arrow.svg", from: :default)
    against = { "icons" => [ default ] }
    lists, found = read("icons:\n  - name: arrow\n    label: Pfeil\n  - name: own\n    label: Own\n    file: own.svg\n", against: against)

    assert_empty found
    arrow, own = lists["icons"]
    assert_equal [ :default, "icons/arrow.svg", "Pfeil" ], [ arrow.from, arrow.file, arrow.label_for("de") ]
    assert_equal [ :theme, "own.svg" ], [ own.from, own.file ]

    _, found = read("icons:\n  - name: unknown\n    label: X\n", against: against)

    assert_equal 1, found.size
    assert_includes found.first, "`file` is missing"
  end

  test "a label is a String or a mapping of languages, read in the interface's language, then English, then the first given" do
    lists, = read("section_styles:\n  - name: a\n    label: Plain\n  - name: b\n    label: { de: Kontakt, en: Contact }\n  - name: c\n    label: { fr: Contact }\n")
    plain, both, french = lists["section_styles"]

    assert_equal %w[Plain Plain], [ plain.label_for("de"), plain.label_for(:en) ]
    assert_equal %w[Kontakt Contact Contact], [ both.label_for("de"), both.label_for("en"), both.label_for("es") ]
    assert_equal %w[Contact Contact], [ french.label_for("en"), french.label_for("de") ]
  end

  test "an unknown list is refused by name, with the three it may be, and settings: with its own sentence" do
    found = one_problem("colours:\n  - name: a\n    label: A\n", "`colours` is not a list a theme may declare: section_styles, page_templates, icons")

    assert found.end_with?("."), found
    one_problem("settings:\n  accent: red\n", "Appearance settings are not built yet.")
  end

  test "an unknown key, a bad name, a duplicate name, a missing label and an unknown page field are one problem each" do
    one_problem("section_styles:\n  - name: a\n    label: A\n    colour: red\n", "section_styles, entry 1", "`colour`")
    one_problem("section_styles:\n  - name: Services\n    label: A\n", "(Services)", "`name`")
    one_problem("section_styles:\n  - name: #{"a" * 41}\n    label: A\n", "`name`")
    one_problem("section_styles:\n  - name: a\n    label: A\n  - name: a\n    label: B\n", "entry 2 (a)", "earlier entry")
    one_problem("section_styles:\n  - name: a\n", "entry 1 (a)", "`label` is missing")
    one_problem("page_templates:\n  - name: a\n    label: A\n    fields: [hero, sidebar]\n", "page_templates, entry 1 (a)", "`fields`")
    one_problem("section_styles:\n  - name: a\n    label: A\n    fields: [hero]\n", "`fields` is not a key")
    one_problem("page_templates:\n  - name: a\n    label: A\n    file: a.svg\n", "`file` is not a key")
  end

  test "values of the wrong kind are one problem each, named by list, place and key, and nothing raises" do
    {
      "section_styles:\n  - name: yes\n    label: A\n" => [ "section_styles, entry 1", "`name`" ],
      "section_styles:\n  - name: 2\n    label: A\n" => [ "`name`", "number 2" ],
      "section_styles:\n  - name: a\n    label:\n" => [ "entry 1 (a)", "`label`" ],
      "section_styles:\n  - name: a\n    label: { en: 3 }\n" => [ "`label`" ],
      "section_styles:\n  - name: a\n    label: { 1: A }\n" => [ "`label`" ],
      "section_styles:\n  - name: a\n    label: [A]\n" => [ "`label`", "a list" ],
      "section_styles:\n  - name: a\n    label: \"  \"\n" => [ "`label`" ],
      "page_templates:\n  - name: a\n    label: A\n    fields: hero\n" => [ "`fields`", "must be a list" ],
      "page_templates:\n  - name: a\n    label: A\n    fields: [1]\n" => [ "`fields`" ],
      "section_styles:\n  - services\n" => [ "section_styles, entry 1", "not the text" ],
      "section_styles:\n  - [a]\n" => [ "entry 1", "a list" ],
      "section_styles: services\n" => [ "section_styles must be a list" ],
      "section_styles:\n" => [ "section_styles must be a list", "empty" ],
      "icons:\n  - name: a\n    label: A\n    file: 3\n" => [ "icons, entry 1 (a)", "`file`" ],
      "- section_styles\n" => [ "must be a mapping of lists", "a list" ],
      "just text\n" => [ "must be a mapping of lists" ],
      "1: x\n" => [ "`1` is not a list" ]
    }.each do |yaml, parts|
      assert_nothing_raised { one_problem(yaml, *parts) }
    end
  end

  test "a YAML error is one problem with its line, an alias and a tag are refused, and a file that is not UTF-8 is one problem" do
    one_problem("section_styles:\n  - name: a\n   label: [\n", "line 2")
    one_problem("a: &x\n  - 1\nsection_styles: *x\n", "an alias and an anchor")
    one_problem("section_styles: !ruby/object:OpenStruct {}\n", "a tag")
    one_problem("section_styles:\n  - name: a\n    label: A\n".dup.force_encoding("ASCII-8BIT") + "\xE9".b, "not UTF-8")
  end

  test "a file of comments only declares nothing" do
    lists, found = read("# nothing yet\n# section_styles:\n")

    assert_empty found
    assert_empty lists
    assert_equal Theme::Declarations.default, Theme::Declarations.default.merge(lists)
  end

  test "the default theme's own file is sound and declares Standard, Landing and no section style" do
    lists = Theme::Declarations.default

    assert_empty Theme::Declarations.read(Rails.root.join("config/theme/default.yml").read, file: "default.yml", against: {}).last
    assert_equal %w[standard landing], lists["page_templates"].map(&:name)
    assert_equal %w[Standard Landing], lists["page_templates"].map { |choice| choice.label_for(:en) }
    assert_equal [ [], [ "hero" ] ], lists["page_templates"].map(&:fields)
    assert_empty lists["section_styles"]
    assert_equal Theme::Contract::CHOICE_LISTS, lists.keys
  end
  test "every explicit tag is refused, standard ones too: !!binary, !!str, !!int and !ruby/object" do
    [ "!!binary 6Q==", "!!str A", "!!int 3", "!ruby/object:OpenStruct {}" ].each do |tagged|
      one_problem("section_styles:\n  - name: a\n    label: #{tagged}\n", "a tag")
    end
    one_problem("section_styles:\n  - name: !!str a\n    label: A\n", "a tag")
  end

  test "an anchor with no alias is refused too" do
    one_problem("section_styles:\n  - &first\n    name: a\n    label: A\n", "an anchor")
  end

  test "deep nesting is one problem on a thread as a request runs on, and a stack that overflows in the parse is one problem too" do
    deep = ("[" * 2000) + ("]" * 2000)
    found = Thread.new { problems("section_styles: #{deep}\n") }.value

    assert_equal 1, found.size, found.inspect
    assert found.first.start_with?("theme.yml"), found.first
    assert_includes found.first, "nested deeper"

    stack = ->(*) { raise SystemStackError }
    found = with_singleton_override(YAML, :safe_load, stack) { Thread.new { problems("section_styles: []\n") }.value }

    assert_equal 1, found.size
    assert_includes found.first, "nested deeper"
  end

  test "a file over 64 KB is refused with one sentence that starts with the file and says what to do" do
    found = problems("# #{"x" * Theme::Declarations::MAX_BYTES}\n")

    assert_equal 1, found.size
    assert found.first.start_with?("theme.yml is larger than 64 KB"), found.first
    assert found.first.end_with?("Cut it down."), found.first
  end

  test "a date or a symbol is a value of the wrong kind, named by list, place and key" do
    one_problem("section_styles:\n  - name: a\n    label: 2024-01-01\n", "section_styles, entry 1 (a)", "`label`", "date")
    one_problem("section_styles:\n  - name: :sym\n    label: A\n", "section_styles, entry 1", "`name`", "symbol")
  end

  test "a key written twice in one mapping is one problem naming the key" do
    one_problem("section_styles:\n  - name: a\n    name: b\n    label: A\n", "`name` is written 2 times")
    one_problem("section_styles: []\nsection_styles: []\n", "`section_styles` is written 2 times")
  end

  test "fields left empty is a problem like an empty list, and an empty list says how to declare none" do
    one_problem("page_templates:\n  - name: a\n    label: A\n    fields:\n", "`fields`", "must be a list")
    one_problem("icons:\n", "`icons: []` for none")
  end

  test "many entries are read in linear time and a repeated name is still found" do
    yaml = "section_styles:\n" + (1..1200).map { |n| "  - name: n#{n}\n    label: L\n" }.join
    lists, found = read(yaml)

    assert_empty found
    assert_equal 1200, lists["section_styles"].size
    assert_equal 1, problems(yaml + "  - name: n7\n    label: L\n").size
  end

  test "a label's language keys are language codes" do
    one_problem("section_styles:\n  - name: a\n    label: { not a code: A }\n", "`label`")
    assert_empty problems("section_styles:\n  - name: a\n    label: { pt-BR: A, de: B }\n")
  end
end
