use jmaptest;
use JMAP::TestSuite::Util qw(email_create_invalid_or_repaired);

test {
  my ($self) = @_;

  my $account = $self->any_account;
  my $tester  = $account->tester;

  $tester->require_capabilities(
    'urn:ietf:params:jmap:core',
    'urn:ietf:params:jmap:mail',
  );

  my $mbox = $account->create_mailbox;

  my $blob = $account->email_blob(generic => {
    body => "My pid is $$",
  });

  # RFC 8621 S4.6: a part "MUST NOT" have both partId and blobId.
  email_create_invalid_or_repaired(
    $tester,
    {
      mailboxIds => { $mbox->id => jtrue },
      bodyStructure => {
        blobId => $blob->blobId,
        partId => 'text',
        type   => 'text/plain',
      },
      bodyValues => {
        text => {
          value => 'ok',
        }
      },
    },
    { properties => [ 'textBody' ] },
    sub {
      my ($email) = @_;
      jcmp_deeply(
        $email->{textBody},
        [ superhashof({ type => 'text/plain' }) ],
        "one text/plain body part, from one source or the other",
      );
    },
    "blobId and partId in bodyStructure",
  );
};
