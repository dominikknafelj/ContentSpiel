module Blocks
  module FormFields
    # One box, also a consent box: the label follows the box and is the
    # box's name. Unticked sends nothing, which `Forms::Answers` reads as no
    # (and a required one refuses). `value` is true (or "1") when ticked.
    class CheckboxComponent < Base
    end
  end
end
