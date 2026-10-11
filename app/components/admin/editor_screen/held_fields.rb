module Admin
  module EditorScreen
    # Makes the fields of a form someone else holds read-only (live-editing
    # spec §4.3, handoff 5 to 7): a text control is `readonly`, so its text
    # stays selectable and at full contrast, and a control HTML cannot make
    # read-only (a select, a checkbox, a radio, a file input, a button) is
    # `disabled`. Hidden fields are left alone, so the form still carries the
    # same names and values as the editable one.
    #
    # ONE PASS OVER THE RENDERED FORM, here, rather than a read-only option on
    # each of the eight components that draw a field: a field component added
    # later is covered the day it is rendered in an editor, and the editable
    # and the held form cannot drift apart (the component tests compare every
    # control's name and value, and everything else of its markup). The
    # browser's counterpart, for the one form that turns read-only in place,
    # is `editing/freeze.js`: the same lists.
    #
    # WHAT THE PARSE KEEPS AND WHAT IT DOES NOT. Parsed with the HTML5
    # parser and written out again, the markup keeps its entities, its
    # attributes' order, `<template>` and `<script type="application/json">`
    # contents, SVG and boolean attributes (`hidden` becomes `hidden=""`, the
    # same attribute). The one thing the round trip loses is a newline at the
    # start of a `textarea`, `pre` or `listing`: the parser drops the first
    # one (the spec says so) and the serializer does not put it back, so a
    # value that began with a newline would lose it in the browser. That is
    # put back here before writing.
    #
    # NEUTRALISED: besides `readonly` and `disabled`, the actions that would
    # write something are taken off (`NEUTRALISED`): adding and removing a
    # chip, choosing or removing a library image, resetting an override,
    # asking for a translation and inserting a picked image or an accepted
    # suggestion into the editor, adding and removing a group, choosing a
    # section layout. A control that only READS (a `details`, a link, the
    # "Copy my text" button of the strip, which is outside the form) is not
    # touched.
    module HeldFields
      TEXT = "input:not([type=hidden]):not([type=checkbox]):not([type=radio]):not([type=file]):not([type=button]):not([type=submit]), textarea".freeze
      OTHER = "select, input[type=checkbox], input[type=radio], input[type=file], button".freeze
      NEUTRALISED = %r{\A(?:[\w:.-]+->)?(?:admin--ui--chip-input#|admin--media--field#|admin--ui--override-field#|admin--translation--translate#|admin--editor--groups#|admin--editor--section#chooseLayout\z|admin--rich-text--editor#(?:picked|applySuggestion)\z)}
      GUARD = '<button type="submit" disabled hidden tabindex="-1" data-held-guard></button>'.freeze
      NEWLINE_FIRST = "textarea, pre, listing".freeze

      module_function

      # `guard: true` puts a disabled submit button first in the markup: a form
      # whose default button is disabled does not submit when Enter is pressed
      # in a field (HTML's implicit submission), and a form with one text
      # field and no button would. The held form has no autosave to catch it.
      def call(html, guard: false)
        fragment = Nokogiri::HTML5.fragment("#{GUARD if guard}#{html}")
        fragment.css(TEXT).each { |field| field["readonly"] = "readonly" }
        fragment.css(OTHER).each { |field| field["disabled"] = "disabled" }
        fragment.css("[data-action]").each { |element| neutralise(element) }
        fragment.css(NEWLINE_FIRST).each { |element| keep_first_newline(element) }
        fragment.to_html.html_safe # rubocop:disable Rails/OutputSafety -- markup this app has just rendered, parsed and written out again
      end

      def neutralise(element)
        kept = element["data-action"].split.grep_v(NEUTRALISED)
        kept.empty? ? element.remove_attribute("data-action") : element["data-action"] = kept.join(" ")
      end

      def keep_first_newline(element)
        first = element.children.first
        first.content = "\n#{first.content}" if first&.text? && first.content.start_with?("\n")
      end
    end
  end
end
