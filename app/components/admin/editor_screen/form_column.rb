# The editors' form column (layout points spec, decisions 1-3): the class that
# caps the post form, the page settings panel and the page's block list at
# --cs-form-max (760px), left-aligned. A translation tab's pairs need two
# columns of up to 560px, so there the cap is --cs-form-max-pair (Claude
# Design's O3).
#
# The class goes on the element that is already there, never on a new wrapper:
# live editing's merge (`app/javascript/editing/merge.js`) needs an id on every
# ancestor of a unit up to the block list, and a wrapper would be one more.
module Admin::EditorScreen::FormColumn
  def self.classes(locale)
    base = "admin-form-column"
    locale.to_s == ::Locales.default.to_s ? base : "#{base} admin-form-column--pair"
  end
end
