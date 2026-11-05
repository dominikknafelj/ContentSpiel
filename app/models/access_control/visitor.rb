module AccessControl
  # A visitor of the public site: nobody signed in,
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
  #
  # ONE INSTANCE. `Visitor::ONE`, which `AccessControl::VISITOR` names, is
  # built here and then `new` and `[]` are made private, so no other code
  # can make a second visitor; the checker and the audit log also ask for
  # THE instance (`equal?`), not the class, so a copy (`dup`, `clone`) is
  # no visitor either. test/lib/visitor_actor_test.rb fails on a
  # construction written anywhere else.
  Visitor = Data.define

  class Visitor
    ONE = new.freeze
    private_class_method :new, :[]

    def self.one?(actor) = actor.equal?(ONE)

    def to_s = "visitor"
  end
end
