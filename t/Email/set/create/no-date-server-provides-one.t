use jmaptest;

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mbox = $account->create_mailbox;

  my ($set_res) = $tester->request_ok(
    [
      "Email/set" => {
        create => {
          new => {
            mailboxIds => { $mbox->id => \1, },
          },
        },
      },
    ],
    superhashof({
      created => {
        new => superhashof({
          id => jstr(),
        }),
      },
    }),
    "minimum required properties provided gives good response",
  );

  my $created_id = $set_res->sentence(0)->as_set->created_id('new');

  $tester->request_ok(
    [
      "Email/get" => {
        ids => [ $created_id ],
        properties => [ 'sentAt' ],
      },
    ],
    superhashof({
      list => [
        {
          id     => $created_id,
          # RFC 8621 S4.6: the server MUST generate a Date header field "in
          # conformance with" RFC 5322 S3.6.1, so header:Date:asDate parses.
          sentAt => re(qr/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d*[1-9])?(?:Z|[+-]\d\d:\d\d)\z/),
        },
      ],
    }),
    "a date header was generated for us",
  );
};
