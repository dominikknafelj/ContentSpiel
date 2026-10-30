# A test mail held in flight, for a system test that presses "Send test mail"
# twice: `ApplicationMailer.deliver_now_and_record` waits on a latch the test
# opens and counts its calls. (The suite has no minitest/mock, so the class
# method is swapped by hand and put back in an `ensure`.)
#
#   with_held_test_mail do |entered, release, calls|
#     press "Send test mail"; entered.pop   # the send is now in the request
#     ...; release << true
#   end
module HeldTestMail
  def with_held_test_mail
    entered = Queue.new
    release = Queue.new
    calls = Concurrent::AtomicFixnum.new(0)
    original = ApplicationMailer.method(:deliver_now_and_record)
    ApplicationMailer.define_singleton_method(:deliver_now_and_record) do |_mail|
      calls.increment
      entered << true
      release.pop
      nil
    end
    yield entered, release, calls
  ensure
    release << true
    ApplicationMailer.define_singleton_method(:deliver_now_and_record, original) if original
  end
end
