module Blocks
  module FormFields
    # One box, also a consent box: the label follows the box and is the
    # box's name. Unticked sends nothing, which `Forms::Answers` reads as no
    # (and a required one refuses). `value` is true when ticked.
    class CheckboxComponent < Base
      private

      def ticked? = value == true || value == "1"

      def control_attributes = super.except(:maxlength)
    end
  end
end
