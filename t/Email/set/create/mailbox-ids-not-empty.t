use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  # RFC 8621 S4.1.1: an Email "MUST belong to one or more Mailboxes at all
  # times (until it is destroyed)".
  my $res = $tester->request([[
    "Email/set" => {
      create => {
        new => {
          mailboxIds => {},
          subject    => "no mailboxes $$",
          bodyStructure => { type => 'text/plain', partId => 'body' },
          bodyValues    => { body => { value => "no mailboxes" } },
        },
      },
    },
  ]]);

  jcmp_deeply(
    $res->single_sentence('Email/set')->arguments->{notCreated},
    { new => invalid_properties('mailboxIds') },
    "create with empty mailboxIds is rejected",
  ) or diag explain $res->as_stripped_triples;
};
