module Admin
  module Fields
    # A checkbox (spec §4.3), for `:boolean` fields, paired with a hidden
    # `"0"` field under the same name -- `check_box_tag` (unlike the
    # model-bound `check_box`/`f.check_box`) doesn't add one on its own, and
    # without it an unchecked checkbox submits nothing at all, which a save
    # can't tell apart from "this field wasn't in the request". The hidden
    # field renders first, so the checkbox's own value (when checked) is
    # what ends up last in the request's `params[name]` -- browsers submit
    # same-named fields in document order, and Rails keeps the last one for
    # a scalar (non-array) param name.
    class BooleanField < Base
      def checked? = ActiveModel::Type::Boolean.new.cast(value) == true
    end
  end
end
