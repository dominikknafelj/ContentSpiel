require "test_helper"

# `TitleSearch`: the two searches of a translated title (one language, every
# language), shared by `Page` and `Post`.
class TitleSearchTest < ActiveSupport::TestCase
  setup do
    Current.actor = users(:one)
    with_locales(%w[en de es], default: "en")
    @page = create_page(title: "Harbour walks", translations: { "de" => { title: "Hafenrunden" } })
    @other_page = create_page(title: "Recipes")
    @post = create_post(title: "Harbour notes")
  end

  test "title_matching finds the text anywhere in that language's title, whatever the case" do
    assert_equal [ @page ], Page.title_matching("ARBOUR", locale: "en").to_a
    assert_equal [ @page ], Page.title_matching("hafen", locale: :de).to_a
    assert_equal [ @post ], Post.title_matching("harbour", locale: "en").to_a
    assert_empty Page.title_matching("lighthouse", locale: "en")
  end

  test "title_matching is literal per language: no other language's title matches" do
    assert_empty Page.title_matching("harbour", locale: "de")
    assert_empty Page.title_matching("hafen", locale: "en")
    # No title at all in that language (NULL from `->>`) is no match, even for
    # the text that matches everything else.
    assert_not_includes Page.title_matching("", locale: "es"), @page
    assert_not_includes Page.title_matching("", locale: "de"), @other_page
    assert_includes Page.title_matching("", locale: "en"), @other_page
  end

  test "title_matching reads a typed % or _ as a character, not a wildcard" do
    percent = create_page(title: "50% off")
    underscore = create_page(title: "snake_case")
    create_page(title: "snakeXcase")

    assert_equal [ percent ], Page.title_matching("%", locale: "en").to_a
    assert_equal [ underscore ], Page.title_matching("e_c", locale: "en").to_a
    assert_empty Page.title_matching("\\", locale: "en")
  end

  test "title_matching composes with a narrowed relation" do
    assert_empty Page.where.not(id: @page.id).title_matching("harbour", locale: "en")
    assert_equal [ @page ], Page.kept.where(id: [ @page.id, @other_page.id ]).title_matching("harbour", locale: "en").to_a
  end

  test "title_matching_any_locale finds the text in any language's title" do
    assert_equal [ @page ], Page.title_matching_any_locale("HAFEN").to_a
    assert_equal [ @page ], Page.title_matching_any_locale("harbour").to_a
    assert_equal [ @post ], Post.title_matching_any_locale("notes").to_a
    assert_empty Page.title_matching_any_locale("lighthouse")
  end

  test "title_matching_any_locale tests the values only, never a locale key or the JSON around them" do
    # "en" and "de" are keys of every title; `{`, `"` and `:` its punctuation.
    assert_empty Page.title_matching_any_locale("en\"")
    assert_empty Page.title_matching_any_locale("\": \"")
    assert_not_includes Page.title_matching_any_locale("de"), @other_page

    quoted = create_page(title: "The \"best\" of")
    assert_equal [ quoted ], Page.title_matching_any_locale("\"best\"").to_a
  end

  test "title_matching_any_locale reads a typed % or _ as a character, not a wildcard" do
    percent = create_page(title: "Plain", translations: { "de" => { title: "50% Rabatt" } })
    underscore = create_page(title: "snake_case")
    create_page(title: "snakeXcase")

    assert_equal [ percent ], Page.title_matching_any_locale("%").to_a
    assert_equal [ underscore ], Page.title_matching_any_locale("e_c").to_a
  end

  # The text and the language reach the query as quoted values, never as SQL:
  # an apostrophe ends no literal, and a "language" is a key to look up.
  test "an apostrophe or a backslash in the text, or a strange language key, is only a value" do
    apostrophe = create_page(title: "Baker's dozen")
    backslash = create_page(title: "C:\\temp")

    assert_equal [ apostrophe ], Page.title_matching("r's d", locale: "en").to_a
    assert_equal [ apostrophe ], Page.title_matching_any_locale("r's d").to_a
    assert_equal [ backslash ], Page.title_matching("c:\\t", locale: "en").to_a
    assert_equal [ backslash ], Page.title_matching_any_locale("\\").to_a
    assert_empty Page.title_matching("harbour", locale: "en' OR '1'='1")
  end

  # The subquery's own table is named `t`; the outer table keeps its name, so
  # the scope works inside a join that also reads `title`.
  test "title_matching_any_locale composes with a narrowed relation and a second scope" do
    assert_equal [ @page ], Page.kept.where(id: [ @page.id, @other_page.id ]).title_matching_any_locale("hafen").title_matching("harbour", locale: "en").to_a
    assert_equal 1, Page.title_matching_any_locale("hafen").count
  end
end
