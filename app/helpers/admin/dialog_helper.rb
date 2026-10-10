module Admin
  # `data:` attributes that make any element open the `Admin::Ui::DialogComponent`
  # with this id: `button_to ..., data: dialog_trigger("delete-tag-3")`.
  # The one `admin--ui--dialog` controller sits on `<body>` (layouts/admin), so
  # the trigger needs no controller of its own and works inside a
  # `<turbo-frame>` or a streamed-in fragment. Mixed into every view by
  # Rails' default `helper :all` and into `Admin::AdminComponent` by hand.
  module DialogHelper
    def dialog_trigger(id)
      { action: "admin--ui--dialog#open", "admin--ui--dialog-id-param": id }
    end
  end
end
