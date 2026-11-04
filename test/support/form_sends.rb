# A visitor's send in a test (forms plan, Task 6; pre-flight ruling R10).
#
# - `aged_drawn(form, age: 1.minute)`: a draw token signed `age` ago, so a
#   send is past `Forms::Drawn::MIN_SECONDS` without a sleep (the sleeps
#   guard refuses one, and a clock moved with `travel_to` is not the
#   browser's). A test of the minimum itself signs with `at:` near now.
# - `clear_form_send_limits`: empties the rate limit's counts
#   (`Forms::SendLimit.store`, a memory store of the process in test), which
#   every test that sends calls first, or the sixth send of a worker from
#   127.0.0.1 is answered 429.
# - `place_form(page, form)`: a Form block naming `form` on `page`, as rows,
#   written as the placements' tests write it (`update_columns`, from before
#   the type was registered in Task 7), and a publish takes it into the
#   page's copy.
module FormSends
  def aged_drawn(form, age: 1.minute) = Forms::Drawn.token(form, at: Time.current - age)

  def clear_form_send_limits = Forms::SendLimit.store.clear

  def place_form(page, form, publish: true)
    block = page.content_blocks.create!(block_type: "rich_text", position: page.content_blocks.count)
    block.update_columns(block_type: "form", settings: { "form_id" => form.id.to_s }) # version: none (a test's row; a publish below moves it)
    publish ? publish_changes(page) : page
  end
end
