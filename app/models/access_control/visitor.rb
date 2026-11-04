module AccessControl
  # A visitor of the public site (forms plan, decision 8): nobody signed in,
  # sending a form. A value with nothing in it, used through the one instance
  # `AccessControl::VISITOR`: there is no visitor record, no id and nothing
  # about the person, because a visitor is nobody the CMS knows.
  #
  # THE BENT RULE. Before forms, "a nil or unknown actor on `:public` is
  # denied everything". Now the visitor may do exactly one thing, the
  # permission `forms.submit` on the channel `:public` (`Checker#allowed?`),
  # and nothing else on any channel; `forms.submit` is registered with
  # `grantable: false`, so no group, token, matrix or seed can hold it and
  # nobody but the visitor is ever allowed it through a grant. Two guards:
  # test/models/access_control/visitor_test.rb (every registered key on
  # every channel) and test/lib/visitor_actor_test.rb (only the endpoint
  # that takes a visitor's send names `AccessControl::VISITOR`).
  #
  # The audit log stores a visitor as no actor, `actor_label` "visitor", no
  # IP (`Audit.record`).
  Visitor = Data.define

  class Visitor
    def to_s = "visitor"
  end
end
